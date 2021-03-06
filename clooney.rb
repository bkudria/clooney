require 'rubygems'
require 'sinatra'

require 'activesupport'
require 'haml'
require 'sass'
require 'typhoeus'
require 'json'

ClooneyError = Class.new(RuntimeError)
class Movie < Struct.new(:name, :character, :release_date, :fandango, :traileraddict, :imdb, :metacritic)
  def release
    (Date.today - Date.parse(release_date)).to_i
  end
end

MQLREAD_BASE_URI = 'http://api.freebase.com/api/service/mqlread'
FREEBASE_HEADERS = {'X-Requested-With' => 'HowManyMoviesIsGeorgeClooneyInRightNow.com 1.0'}

CURRENT_PARAMS  = ['-film.initial_release_date', 3.months.ago.to_date, Date.today]
UPCOMING_PARAMS = ['film.initial_release_date', Date.today, 5.years.from_now.to_date]

configure do
  set    :haml, {:format => :html5}
  set    :sass, {:style  => :compact}
  enable :logging
  enable :static
end

configure :development do
  FREEBASE_HEADERS = FREEBASE_HEADERS.merge({'Cache-Control' => "no-cache"})
end

configure :production do
  disable :logging
  set :port, 80
end

helpers do
  def gen_mql_query(sort_key, from, to)
    JSON[File.read('clooney_movies.mql') % [sort_key, from.to_date, to.to_date]]
  end

  def query_freebase(query)
    query_uri = "#{MQLREAD_BASE_URI}?query=#{{:query => query}.to_json}"
    response  = Typhoeus::Request.get(query_uri,
                                      :headers       => FREEBASE_HEADERS,
                                      :timeout       => 5000, # 5 Seconds
                                      :cache_timeout => 3600) # 1 Hour
    return response.code == 200 ? response.body : nil
  end

  def extract_movies response_body
    return nil if response_body.nil?
    movies = JSON[response_body]["result"].map do |json|
      m = Movie.new
      m.name          = json["film"]["name"]
      m.release_date  = json["film"]["initial_release_date"]
      m.character     = json["character"]["name"] if json["character"]
      [:imdb, :fandango, :traileraddict, :metacritic].each do |key|
        mql_key = "#{key}:key"
        m[key] = json["film"][mql_key]["value"] if json["film"][mql_key] and json["film"][mql_key]["value"]
      end
      m
    end
  end
end

get '/' do
  response["Cache-Control"] = "public, max-age=3600"
  @title = "How many movies is George Clooney in right now?"
  @current_movies  = extract_movies(query_freebase(gen_mql_query(*CURRENT_PARAMS)))
  @upcoming_movies = extract_movies(query_freebase(gen_mql_query(*UPCOMING_PARAMS)))
  if @current_movies.nil?
    raise ClooneyError
  else
    haml :index
  end
end

get '/style.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :style
end

not_found do
  haml :notfound
end

error ClooneyError do
  haml :error
end

error do
  haml :error
end
