require 'sinatra/base'

class BeezlobiaApi < Sinatra::Application
  include Hatchet

  Hatchet.configure do |config|
    config.level :debug

    config.appenders << Hatchet::LoggerAppender.new do |appender|
      appender.logger = Logger.new('log/application.log')
    end
    config.appenders << Hatchet::LoggerAppender.new do |appender|
      appender.logger = Logger.new(STDOUT)
    end
  end

  DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/beezlobia.db")

  class SystemSettings
    include DataMapper::Resource
    property    :id,        Serial
    property    :setting,   String, required: true
    property    :value,     String
  end
  DataMapper.finalize

  def somfy_client_id
    ENV['SOMFY_CLIENT_ID']
  end

  def somfy_client_secret
    ENV['SOMFY_CLIENT_SECRET']
  end

  get '/health' do
    "OK"
  end

  get '/oauth/somfy' do
    unless somfy_client_id
      halt 500, "SOMFY_CLIENT_ID not configured"
    end

    redirect_uri = URI.parse(request.url)
    redirect_uri.path = "/oauth/somfy/callback"

    auth_url = URI.parse("https://accounts.somfy.com/oauth/oauth/v2/auth")
    auth_url.query = URI.encode_www_form({
      response_type: :code,
      client_id: ENV['SOMFY_CLIENT_ID'],
      redirect_uri: redirect_uri.to_s,
      grant_type: :authorization_code,
    })
    log.info "redirecting to #{auth_url.to_s}"

    redirect to(auth_url.to_s)
  end
end