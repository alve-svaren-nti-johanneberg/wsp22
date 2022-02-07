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

def group_number(num, length = 3)
  # 12345 => 12 345
  num.to_s.chars.reverse.each_slice(length).reverse_each.map { |x| x.reverse.join }.join(' ')
end

def get_human_readable_price(price)
  price.positive? ? "#{group_number(price, 3)} kr" : 'Gratis'
end
