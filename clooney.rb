require 'rubygems'
require 'sinatra'

require 'activesupport'
require 'haml'
require 'sass'
require 'typhoeus'
require 'exceptional'
require 'json'

class Movie < Struct.new(:name, :character, :release_date, :fandango, :traileraddict, :imdb, :metacritic)
  def release
    (Date.today - Date.parse(release_date)).to_i
  end
end

Exceptional.api_key = "ffaba9615edc90a149e12bc70f66f946681bb3ab"
module Exceptional
  def self.handle_sinatra(exception, uri, request, params)
    e = Exceptional.parse(exception)

    e.framework = "sinatra"
    e.controller_name = uri
    e.occurred_at = Time.now.strftime("%Y%m%d %H:%M:%S %Z")
    e.environment = request.env.to_hash
    e.url = uri
    e.parameters = params.to_hash

    Exceptional.post e
  end
end

MQLREAD_BASE_URI = 'http://api.freebase.com/api/service/mqlread'
FREEBASE_HEADERS = {'X-Requested-With' => 'Secret App 1.0'}

CURRENT_RANGE  = [3.months.ago.to_date, Date.today]
UPCOMING_RANGE = [Date.today, 5.years.from_now.to_date]

configure do
  enable  :logging
  enable  :static
  set :haml, {:format => :html5}
  set :sass, {:style => :compact}
end

configure :development do
  FREEBASE_HEADERS = {'X-Requested-With' => 'Secret App 1.0', 'Cache-Control' => "no-cache"}
end

configure :production do
  disable :logging
  set :port, 80
end

helpers do
  def gen_mql_query(from, to)
    JSON[File.read('clooney_movies.mql') % [from.to_date, to.to_date]]
  end

  def query_freebase(query)
    query_uri = "#{MQLREAD_BASE_URI}?query=#{{:query => query}.to_json}"
    response = Typhoeus::Request.get(
                                     query_uri,
                                     :headers => FREEBASE_HEADERS,
                                     :timeout => 5000,      # 5 Seconds
                                     :cache_timeout => 3600 # 1 Hour
                                     )
    return response.code == 200 ? response.body : nil
  end

  def extract_movies response_body
    return nil if response_body.nil?
    movies = JSON[response_body]["result"].map do |json|
      m = Movie.new
      m.name          = json["film"]["name"]
      m.character     = json["character"]["name"] if json["character"]
      m.release_date  = json["film"]["initial_release_date"]
      [:imdb, :fandango, :traileraddict, :metacritic].each do |key|
        mql_key = "#{key}:key"
        m[key] = json["film"][mql_key]["value"] if json["film"][mql_key] and json["film"][mql_key]["value"]
      end
      m
    end
  end
end

get '/' do
  @title = "How many movies is George Clooney in right now?"
  @current_movies  = extract_movies(query_freebase(gen_mql_query(*CURRENT_RANGE)))
  @upcoming_movies = extract_movies(query_freebase(gen_mql_query(*UPCOMING_RANGE)))
  if @current_movies.nil?
    haml :error
  else
    haml :index
  end
end

get '/style.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :style
end

not_found do
  Exceptional.handle_sinatra(request.env['sinatra.error'], request.env['REQUEST_URI'], request, params)
  haml :notfound
end

error do
  Exceptional.handle_sinatra(request.env['sinatra.error'], request.env['REQUEST_URI'], request, params)
  haml :error
end
