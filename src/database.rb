# frozen_string_literal: true

require 'bcrypt'
require 'sqlite3'
require_relative 'utils'

def db
  tmp = SQLite3::Database.new 'data.db'
  tmp.results_as_hash = true
  tmp
end

# An abstract class for all database objects
class DbModel
  def self.table_name; end

  def self.create_table; end
end

# A user
class User < DbModel
  attr_reader :id, :email, :name

  def self.table_name
    'Users'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS \"#{table_name}\" (
      \"id\"	INTEGER NOT NULL UNIQUE,
      \"name\"	TEXT NOT NULL UNIQUE,
      \"email\"	TEXT NOT NULL UNIQUE,
      \"password_hash\"	BLOB NOT NULL,
      PRIMARY KEY(\"id\" AUTOINCREMENT))")
  end

  def initialize(data)
    super()
    @id = data['id']
    @email = data['email']
    @name = data['name']
    @password_hash = BCrypt::Password.new(data['password_hash'])
  end

  def self.create(email, password)
    hash = BCrypt::Password.create(password)
    session = db
    return nil unless validate_email(email)
    return nil unless session.execute('SELECT * FROM Users WHERE email = ?', email).empty?

    session.execute('INSERT INTO Users (email, password_hash) VALUES (?, ?)', email, hash)
    session.last_insert_row_id
  end

  def self.find_by_id(id)
    data = db.execute("SELECT * FROM #{table_name} WHERE id = ?", id).first
    data && User.new(data)
  end

  def self.find_by_email(email)
    return nil if email.empty?

    data = db.execute('SELECT * FROM Users WHERE email = ?', email).first
    data && User.new(data)
  end

  def verify_password(password)
    @password_hash == password
  end

  def ads
    db.execute('SELECT * FROM Ads WHERE seller = ?', @id).map do |ad|
      Ad.new(ad)
    end
  end
end

# An ad that a user created
class Ad < DbModel
  attr_reader :id, :price, :seller, :title, :content, :sold, :postal_code

  def self.table_name
    'Ads'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS \"Ads\" (
      \"id\"	INTEGER NOT NULL UNIQUE,
      \"price\"	INTEGER NOT NULL,
      \"title\"	TEXT NOT NULL,
      \"content\"	TEXT NOT NULL,
      \"sold\"	INTEGER NOT NULL DEFAULT 0,
      \"seller\"	INTEGER NOT NULL,
      \"postal_code\" TEXT NOT NULL,
      FOREIGN KEY(\"seller\") REFERENCES \"Users\"(\"id\"),
      PRIMARY KEY(\"id\" AUTOINCREMENT))")
  end

  def initialize(data)
    super()
    @id = data['id']
    @price = data['price']
    @seller = User.find_by_id(data['seller'])
    @title = data['title']
    @postal_code = data['postal_code']
    @content = data['content']
    @sold = data['sold']
  end

  def self.find_by_id(id)
    data = db.execute("SELECT * FROM #{table_name} WHERE id = ?", id).first
    data && Ad.new(data)
  end

  def self.create(title, content, price, seller_id, postal_code)
    session = db
    session.execute('INSERT INTO Ads (title, content, price, seller, postal_code) VALUES (?, ?, ?, ?, ?)',
                    title, content, price, seller_id, postal_code)
    session.last_insert_row_id
  end

  def self.search(words)
    query = words.empty? && 'SELECT * FROM Ads'
    wildcards = words.map do
      'title LIKE ?'
    end
    words.map! do |word|
      "%#{word}%"
    end
    db.execute(query || "SELECT * FROM Ads WHERE #{wildcards.join(' AND ')}", words).map do |data|
      Ad.new(data)
    end
  end

  def delete
    db.execute('DELETE FROM Ads WHERE id = ?', @id)
  end
end

User.create_table
Ad.create_table
