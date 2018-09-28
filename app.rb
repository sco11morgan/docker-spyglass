require 'sinatra'
require "sinatra/reloader" if development?


configure :production, :development do
  enable :logging
 enable :sessions
end

helpers do
  def image
    session[:image] ? session[:image] : 'Image needed'
  end
end

get '/' do
  erb :index
end

get '/image' do
  session[:image] = params['image']
  image = params['image']
  erb :"image/index"
end

get '/tags/all' do
  'all tags'
end

get '/tags' do
  'sorted tags'
end
