require 'sinatra/base'
require 'hatchet'
require 'data_mapper'

Hatchet.configure do |config|
  config.level :debug

  config.appenders << Hatchet::LoggerAppender.new do |appender|
    appender.logger = Logger.new('log/application.log')
  end
  config.appenders << Hatchet::LoggerAppender.new do |appender|
    appender.logger = Logger.new(STDOUT)
  end
end

class Settings
  include Hatchet

  DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/beezlobia.db")

  class SystemSettings
    include DataMapper::Resource
    property    :id,        Serial
    property    :setting,   String, required: true
    property    :value,     String, length: 256
  end
  DataMapper.auto_migrate!


  def self.get(key)
    SystemSettings.all(setting: key).first&.value
  end

  def self.set(key, value)
    unless setting = SystemSettings.all(setting: key).first
      setting = SystemSettings.new(setting: key)
    end
    setting.value = value

    unless setting.save
      log.error ".set key=#{key} value=#{value} failed with #{setting.errors.full_messages}"
      raise setting.errors.full_messages
    end
    value
  end

  def self.somfy_client_id
    ENV['SOMFY_CLIENT_ID']
  end

  def self.somfy_client_secret
    ENV['SOMFY_CLIENT_SECRET']
  end
end

DataMapper.finalize

class BeezlobiaApi < Sinatra::Application
  include Hatchet

  def auth_redirect_uri
    redirect_uri = URI.parse(request.url)
    redirect_uri.path = "/auth/somfy/callback"
    redirect_uri.to_s
  end

  get '/health' do
    "OK"
  end

  get '/status' do
    if somfy_access_token = Settings.get('somfy_access_token')
      "Authorized - #{somfy_access_token.value}"
    else
      "Not Authorized"
    end
  end

  get '/settings/:key' do
    Settings.get(params['key'])
  end

  post '/settings/:key' do
    request.body.rewind
    Settings.set(params['key'], request.body.read)
  end

  get '/auth/somfy' do
    unless Settings.somfy_client_id
      halt 500, "somfy_client_id not configured"
    end

    unless Settings.somfy_client_secret
      halt 500, "somfy_client_secret not configured"
    end

    log.info { "/auth/somfy auth_redirect_uri=#{auth_redirect_uri}" }

    auth_url = URI.parse("https://accounts.somfy.com/oauth/oauth/v2/auth")
    auth_url.query = URI.encode_www_form({
      response_type: :code,
      client_id: Settings.somfy_client_id,
      redirect_uri: auth_redirect_uri,
      grant_type: :authorization_code,
      state: 'bilge',
    })
    log.info "redirecting to #{auth_url.to_s}"

    redirect to(auth_url.to_s)
  end

  get '/oauth/somfy/callback' do
    token_url = URI.parse("https://accounts.somfy.com/oauth/oauth/v2/token")
    token_url.query = URI.encode_www_form({
      client_id: Settings.somfy_client_id,
      client_secret: Settings.somfy_client_secret,
      grant_type: :authorization_code,
      code: params['code'],
      redirect_uri: auth_redirect_uri,
    })

    response = Faraday.post(token_url)

    payload = JSON.parse(response.body, symbolize_names: true)

    Settings.set :somfy_access_token, payload[:access_token]
    Settings.set :somfy_refresh_token, payload[:refresh_token]
  end

  post '/blinds/:blind_id/close' do
    log.info "Called with #{params['blind_id']}"
  end
end