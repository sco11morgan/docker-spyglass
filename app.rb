require 'sinatra'
require "sinatra/reloader" if development?

require_relative "fetch"

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
  if image.nil? || image.empty?
    @error = "Image is required"
  else
    fetcher = Spyglass::Fetch.new(docker_image: image)
    tags =fetcher.tags
    image_mash = Spyglass::Fetch.new(docker_image: image).view
  end

  erb :"image/index", locals: {image_mash: image_mash, tags: tags}
end

get '/tags/all' do
  'all tags'
end

get '/tags' do
  'sorted tags'
end
