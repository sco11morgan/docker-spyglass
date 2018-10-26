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

get '/test' do
  erb :test
end

get '/image' do
  session[:image] = params['image']
  image = params['image']
  if image.nil? || image.empty?
    @error = "Image is required"
  else
    fetcher = Spyglass::Fetch.new(docker_image: image)
    tags =fetcher.tags
    result = fetcher.view
  end

  erb :"image/index", locals: result.merge(tags: tags)
end

get '/compare' do
  session[:image] = params['image']
  image = params['image']
  if image.nil? || image.empty?
    @error = "Image is required"
  else
    fetcher = Spyglass::Fetch.new(docker_image: image)
    result = fetcher.score(params['tag1'], params['tag2'], true)
    tags =fetcher.tags
  end

  erb :"compare/index", locals: result.merge(tags: tags)
end

get '/tags/all' do
  'all tags'
end

get '/tags' do
  image = params['image']
  fetcher = Spyglass::Fetch.new(docker_image: image)
  JSON.generate(fetcher.tags)
end
