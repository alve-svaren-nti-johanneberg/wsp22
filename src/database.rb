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
  attr_reader :id

  def self.table_name; end

  def self.create_table; end

  def table_name
    self.class.table_name
  end

  def initialize(data)
    @id = data['id']
  end

  def ==(other)
    return false if other.nil?

    @id == other.id
  end

  def self.find_by_id(id)
    data = db.execute("SELECT * FROM #{table_name} WHERE id = ?", id).first
    data && self.class.new(data)
  end
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
      \"name\"	TEXT NOT NULL,
      \"email\"	TEXT NOT NULL UNIQUE,
      \"password_hash\"	BLOB NOT NULL,
      \"admin\" BOOL,
      PRIMARY KEY(\"id\" AUTOINCREMENT))")
  end

  def initialize(data)
    super data
    @email = data['email']
    @name = data['name']
    @admin = data['admin'] || false
    @password_hash = BCrypt::Password.new(data['password_hash'])
  end

  def self.create(name, email, password)
    hash = BCrypt::Password.create(password)
    session = db
    return nil unless session.execute("SELECT * FROM #{table_name} WHERE email = ?", email).empty?

    session.execute("INSERT INTO #{table_name} (name, email, password_hash) VALUES (?, ?, ?)", name, email, hash)
    session.last_insert_row_id
  end

  def self.find_by_email(email)
    return nil if email.empty?

    data = db.execute("SELECT * FROM #{table_name} WHERE email = ?", email).first
    data && User.new(data)
  end

  def verify_password(password)
    @password_hash == password
  end

  def ads
    db.execute("SELECT * FROM #{Ad.table_name} WHERE seller = ?", @id).map do |ad|
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
    db.execute("CREATE TABLE IF NOT EXISTS \"#{table_name}\" (
      \"id\"	INTEGER NOT NULL UNIQUE,
      \"price\"	INTEGER NOT NULL,
      \"title\"	TEXT NOT NULL,
      \"content\"	TEXT NOT NULL,
      \"sold\"	INTEGER NOT NULL DEFAULT 0,
      \"seller\"	INTEGER NOT NULL,
      \"postal_code\" TEXT NOT NULL,
      FOREIGN KEY(\"seller\") REFERENCES \"#{User.table_name}\"(\"id\"),
      PRIMARY KEY(\"id\" AUTOINCREMENT))")
  end

  def initialize(data)
    super data
    @id = data['id']
    @price = data['price']
    @seller = User.find_by_id(data['seller'])
    @title = data['title']
    @postal_code = data['postal_code']
    @content = data['content']
    @sold = data['sold']
  end

  def self.create(title, content, price, seller_id, postal_code)
    session = db
    session.execute("INSERT INTO #{table_name} (title, content, price, seller, postal_code) VALUES (?, ?, ?, ?, ?)",
                    title, content, price, seller_id, postal_code)
    session.last_insert_row_id
  end

  def self.search(words)
    query = words.empty? && "SELECT * FROM #{table_name}"
    wildcards = words.map do
      'title LIKE ?'
    end
    words.map! do |word|
      "%#{word}%"
    end
    db.execute(query || "SELECT * FROM #{table_name} WHERE #{wildcards.join(' AND ')}", words).map do |data|
      Ad.new(data)
    end
  end

  def delete
    db.execute("DELETE FROM #{table_name} WHERE id = ?", @id)
  end
end

User.create_table
Ad.create_table
