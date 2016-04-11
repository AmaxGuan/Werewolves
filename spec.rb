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
    ENV["RACK_ENV"] = "test" # use this to trigger server to not wait before changing status
    Room.clear
  end

  def check_next_move(move)
    get '0/cur_move'
    assert last_response.ok?
    json_body = Yajl::Parser.parse(last_response.body)
    assert_equal move, json_body['cur_move']
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
    check_next_move('all_close')
  end

  def test_one_werewolf_game_ok
    #signin
    post '/create_room', params={:num_players => 2, :num_werewolves => 1}
    assert last_response.ok?
    assert_equal '{"room_id":0}', last_response.body
    post '/0/user_signin/1'
    assert last_response.ok?
    json_body = Yajl::Parser.parse(last_response.body)
    assert_equal true, json_body['succeed']
    post '/0/user_signin/2'
    assert last_response.ok?
    json_body = Yajl::Parser.parse(last_response.body)
    assert_equal true, json_body['succeed']

    #cur_move changes
    get '0/room_info'
    json_body = Yajl::Parser.parse(last_response.body)
    wolf = json_body["users"]["1"]["card"] == "werewolf" ? 1 : 2
    villager = wolf == 1 ? 2 : 1

    check_next_move('all_close')
    check_next_move('werewolves_open')
    check_next_move('werewolves_kill')

    #werewolf_kill
    post "0/take_action/#{wolf}", params={:action => 'werewolf_kill', :target => villager}
    assert last_response.ok?

    check_next_move('werewolves_close')
    check_next_move('werewolves_win')
  end

end