require 'rubygems'
require 'sinatra/base'

require 'activesupport'
require 'haml'
require 'sass'

class Clooney < Sinatra::Base

  set :haml, {:format => :html5}
  set :sass, {:style => :compact}

  CURRENT_MQL_QUERY  = File.read('clooney_movies.mql') % [3.months.ago.to_date, Date.today]
  UPCOMING_MQL_QUERY = File.read('clooney_movies.mql') % [Date.today, 5.year.from_now]

  configure do
    enable :logging
    enable :static
  end

  configure :production do
    disable :logging
    set :port, 80

    correct_password = File.read('password').strip

    use Rack::Auth::Basic do |username, password|
      [username, password] == ['admin', 'max']
    end
  end

  get '/' do
    haml :index
  end

  get '/style.css' do
    content_type 'text/css', :charset => 'utf-8'
    sass :style
  end

  not_found do
    haml :error
  end

  error do
    haml :error
  end
end
