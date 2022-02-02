# frozen_string_literal: true

require 'bcrypt'
require 'sqlite3'

class DbModel
  def self.table_name; end

  def self.create_table; end

  def self.db
    tmp = SQLite3::Database.new 'data.db'
    tmp.results_as_hash = true
    tmp
  end

  def self.find_by_id(id)
    data = db.execute("SELECT * FROM #{table_name} WHERE id = ?", id).first
    data && User.new(data)
  end
end

class User < DbModel
  attr_reader :id, :email

  def self.table_name
    'Users'
  end

  def self.create_table
    db.execute("CREATE TABLE IF NOT EXISTS \"#{table_name}\" (
      \"id\"	INTEGER NOT NULL UNIQUE,
      \"email\"	TEXT NOT NULL UNIQUE,
      \"password_hash\"	BLOB NOT NULL,
      PRIMARY KEY(\"id\" AUTOINCREMENT))")
  end

  def initialize(data)
    super
    @id = data['id']
    @email = data['email']
    @password_hash = BCrypt::Password.new(data['password_hash'])
  end

  def self.create(email, password)
    hash = BCrypt::Password.create(password)
    session = db
    session.execute('INSERT INTO Users (email, password_hash) VALUES (?, ?)', email, hash)
    session.last_insert_row_id
  end

  def self.find_by_email(email)
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

class Ad < DbModel
  attr_reader :id, :price, :seller, :title, :content, :sold

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
      FOREIGN KEY(\"seller\") REFERENCES \"Users\"(\"id\"),
      PRIMARY KEY(\"id\" AUTOINCREMENT)
    )")
  end

  def initialize(data)
    super 'Ads'
    @id = data['id']
    @price = data['price']
    @seller = User.find_by_id(['seller'])
    @title = data['title']
    @content = data['content']
    @sold = data['sold']
  end

  def self.create(title, content, price, seller_id)
    session = db
    session.execute('INSERT INTO Ads (title, content, price, seller) VALUES (?, ?, ?, ?)',
                    title, content, price, seller_id)
    session.last_insert_row_id
  end
end

User.create_table
Ad.create_table
