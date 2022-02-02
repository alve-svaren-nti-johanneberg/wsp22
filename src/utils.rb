# frozen_string_literal: true

require 'sinatra'
require_relative 'database'

def temp_session(symbol)
  value = session[symbol]
  session.delete(symbol)
  value
end

def current_user
  User.find_by_id(session[:user_id])
end

def validate_email(email)
  (/\A[a-z0-9+-_.]+@[a-z\d\-.]+\.[a-z]+\z/i).match?(email)
end

def get_human_readable_price(price)
  price.positive? ? "#{price} kr" : 'Gratis'
end
