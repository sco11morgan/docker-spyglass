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
    result = fetcher.compare(params['tag1'], params['tag2'], true)
    tags =fetcher.tags
  end

  erb :"compare/index", locals: result.merge(tags: tags)
end

get '/trend' do
  session[:image] = params['image']
  image = params['image']
  if image.nil? || image.empty?
    @error = "Image is required"
  else
    fetcher = Spyglass::Fetch.new(docker_image: image)
    trend = fetcher.trend.reverse
    pp trend
    tags = trend.map { |t| ["#{t[:tag1]} -> #{t[:tag2]}", t[:tag2_created][0..9]] }
    result = {tags: tags, size: trend.map { |t| t[:image2_size] }, percent_reuse: trend.map{ |t| t[:percent_reuse] } }
  end

  erb :"trend/index", locals: result, layout: nil
end

get '/tags/all' do
  'all tags'
end

get '/tags' do
  image = params['image']
  fetcher = Spyglass::Fetch.new(docker_image: image)
  JSON.generate(fetcher.tags)
end
