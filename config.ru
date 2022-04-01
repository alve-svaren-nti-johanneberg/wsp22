# frozen_string_literal: true

require 'sinatra'

set :environment, :production

require_relative './src/app'

run Sinatra::Application
