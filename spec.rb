ENV['RACK_ENV'] = 'test'

require './server'
require 'test/unit'
require 'rack/test'
require 'yajl'

class ServerTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    Room.clear
  end

  def test_create_room_ok
    post '/create_room', params={:num_players => 9, :num_werewolves => 3, :seer => 'true'}
    assert last_response.ok?
    assert_equal '{"room_id":0}', last_response.body
  end

  def test_create_room_and_signin_ok
    post '/create_room', params={:num_players => 1, :num_werewolves => 1}
    assert last_response.ok?
    assert_equal '{"room_id":0}', last_response.body
    post '/0/user_signin/1'
    assert last_response.ok?
    json_body = Yajl::Parser.parse(last_response.body)
    assert_equal true, json_body['succeed']
    get '0/cur_move'
    assert last_response.ok?
    json_body = Yajl::Parser.parse(last_response.body)
    assert_equal 'all_close', json_body['cur_move']
  end
end