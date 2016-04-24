require 'sinatra'
require 'yajl'
require 'pry-byebug'

set :bind, '0.0.0.0'
set :port, 80


#game logic, a state machine, start with :user_signin, and end with either :villagers_win, :werewolves_win or :cupit_win
START = :user_signin

# each scene consist of 2 or 3 parts, (who, action, first night or not) concatenated by _

SCENES = [
  :all_close,
  :cupit_open_1st,
  :cupit_connect_1st,
  :cupit_close_1st,
  :cupit_allOpen_1st,
  :cupit_allCheckCouple_1st, # if couple, couple can be displayed on user's screen
  :cupit_allClose_1st,
  :cupit_coupleOpen_1st,
  :cupit_coupleClose_1st,  
  :werewolves_open,
  :werewolves_kill,
  :werewolves_close,
  :witch_open,
  :witch_rescue,
  :witch_poison,
  :witch_close,
  :seer_open,
  :seer_check,
  :seer_checkResult,
  :seer_close,
  :all_open,
  :all_compaign_1st,
  :reveal_death,
  :all_speakAndBanish,
  :banished_action,
  :dead_lastWords,
].freeze

AUTO_COMPLETE_SCENES = [
  :all_close,
  :cupit_open_1st,
  :cupit_close_1st,
  :all_open_1st,
  :all_checkCouple_1st,
  :all_close_1st,
  :werewolves_open,
  :werewolves_close,
  :witch_open,
  :witch_close,
  :seer_open,
  :seer_checkResult,
  :seer_close,
  :all_open,
  :reveal_death,
  :dead_lastWords,
  :banished_action,
].freeze

FINISHES = [
  :villagers_win,
  :werewolves_win,
  :cupit_win
]

GODS = [
  :seer,
  :witch,
  :hunter,
  :idiot,
  :cupit
]

class Room
  # static hash to store all game status, key is room number, value stores the state for each room,
  # finished games will be removed from the global hash
  @@rooms = {}

  # size of rooms, use hash for rooms, so that finished games could be recycled
  @@size = 0

  attr_reader :id, :gods, :night, :cur_move, :cards, :votes, :users

  def self.get_room(room_id)
    @@rooms[Integer(room_id)]
  end

  def self.clear
    @@rooms = {}
    @@size = 0
  end

  def initialize(num_players, num_werewolves, gods)
    @id = @@size
    @@rooms[@@size] = self
    @@size += 1
    @gods = gods
    @num_players = num_players
    @num_werewolves = num_werewolves
    @night = 1
    @cur_move = :user_signin
    card_shuffler = []
    num_werewolves.times {card_shuffler.push(:werewolf)}
    card_shuffler += gods
    card_shuffler.push(:villager) while card_shuffler.size < num_players
    card_shuffler.shuffle!
    @cards = (1..num_players).to_a.zip(card_shuffler).to_h
    @users = {}
    (1..num_players).to_a.zip(card_shuffler).each do |uid, card|
      users[uid] = User.create(uid, card, @id)
    end
    @votes = {}
    @werewolf_kills = {}
    @banishes = {}
    @witch_poison = {}
    @witch_rescue = {}
    @seer_checks = {}
  end

  def get_user(user_id)
    users[Integer(user_id)]
  end

  def _next_move(cur_move)
    next_index = (SCENES.index(cur_move) + 1) % SCENES.size
    SCENES[next_index]
  end

  def get_next_move
    return nil if FINISHES.include? cur_move
    possible_next = _next_move(cur_move)
    if @night != 1 then
      possible_next = _next_move(possible_next) while possible_next.to_s.end_with?('1st')
    end
    #skip , use loop do to simulate do while, see http://rosettacode.org/wiki/Loops/Do-while#Ruby
    loop do
      before_skip = possible_next    
      GODS.each do |god|
        if !@gods.include?(god) then
          while possible_next.to_s.start_with?(god.to_s)
            possible_next = _next_move(possible_next)
          end
        end
      end
      break if before_skip == possible_next
    end
    possible_next
  end

  def go_next_move
    return if FINISHES.include? cur_move
    if @cur_move == :user_signin
      @cur_move = :all_close
      return
    end
    possible_next = get_next_move
    @cur_move = possible_next
    if AUTO_COMPLETE_SCENES.include? @cur_move then
      go_next_move_with_delay(5)
    else
      @time_go_next_move = nil
    end
    @night += 1 if @cur_move == :all_close
    @cur_move
  end

  def go_next_move_with_delay(time_in_sec)
      delay = ENV["RACK_ENV"] == "test" ? 0 : time_in_sec
      @time_go_next_move = Time.new + delay
  end

  # routine check, invoked in every heart beat function
  def heart_beat_check
    go_next_move if !@time_go_next_move.nil? && Time.new  >= @time_go_next_move
    check_finish
  end

  ### game logic section ###
  def user_signin(uid)
    @login_users = [] if @login_users.nil?
    @login_users.push(uid)
    if @login_users.size == @num_players then
      start_game
    end
  end

  def start_game
    go_next_move_with_delay(5)
    @night = 1
  end

  def get_num_living_werewolves
    get_num_living_by_category[:werewolf]
  end

  def get_num_living_by_category
    stats = {}
    @users.each do |id, user|
      role = user.card
      role = :god if GODS.include? user.card
      stats[role] = 0 if stats[role].nil?
      stats[role] += 1 if user.is_dead == false
    end
    stats
  end

  def get_wolveskill_tonight
    @werewolf_kills[@night]
  end

  def get_death_night
    kill = get_wolveskill_tonight == @witch_rescue[@night] ? nil : get_wolveskill_tonight
    [kill, @witch_poison[@night]].compact
  end

  def check_finish
    stats = get_num_living_by_category
    @cur_move = :werewolves_win if stats[:villager] == 0 || stats[:god] == 0
    @cur_move = :villagers_win if stats[:werewolf] == 0
  end

  def werewolf_kill(from, to)
    from_user = get_user(from)
    to_user = get_user(to)
    raise :wrong_action if from_user.card != :werewolf || from_user.is_dead || to_user.is_dead
    @werewolf_kills[@night] = to
    to_user.is_dead=true
    go_next_move
  end

  def seer_check(from, to)
    from_user = get_user(from)
    to_user = get_user(to)
    if from_user.card != :seer ||
        (from_user.is_dead && !get_death_night.include?(@from_user.id)) ||
        cur_move != :seer_check ||
        !@seer_checks[@night].nil? then
      raise :wrong_action
    end
    @seer_checks[@night] = to_user.id
    go_next_move
    to_user.card == :werewolf ? 'BAD' : 'GOOD'
  end

  def witch_can_rescue?
    @witch_rescue.empty?
  end

  def witch_rescue(from)
    from_user = get_user(from)
    to_user = get_user(get_wolveskill_tonight)
    raise :wrong_action if from_user.card != :witch || !witch_can_rescue? || get_wolveskill_tonight == from
    @witch_rescue[@night] = get_wolveskill_tonight
    to_user.is_dead = false
    go_next_move
  end

  def witch_poison(from, to)
    from_user = get_user(from)
    to_user = get_user(to)
    raise :wrong_action if from_user.card != :witch || !@witch_poison.empty?
    @witch_poison[@night] = to
    to_user.is_dead = true
    go_next_move
  end

  def select_police(uid)
    user = get_user(uid)
    @police = user.id
    user.is_police = true
    go_next_move
  end

  def select_banish(uid)
    user = get_user(uid)
    @banishes[@night] = user.id
    user.is_dead = true
    go_next_move
  end

  #might not be useful, because we could have god enter who's dead directly, but in case
  def vote(from, to)
    from_user = get_user(from)
    to_user = get_user(to)
    cur_votes = case cur_move
    when :citizens_vote_1st
      @votes[:police_vote] = {} if @votes[:police_vote].nil?
      raise :wrong_action if from_user.is_candidate
      @votes[:police_vote]
    when :all_vote
      @votes[@night] = {} if @votes[@night].nil?
      @votes[@night]
    end
    raise :wrong_action if from_user.is_dead || to_user.is_dead
    raise :wrong_action if from_user.is_dead || to_user.is_dead
    cur_votes[to] = [] if cur_votes[to].nil?
    cur_votes[to].push(from)
  end

  #might not be useful, because we could have god enter who's dead directly, but in case
  def get_most_voted(votes)
    max_vote = 0
    winners = []
    votes.each do |to, froms|
      sum = 0
      froms.each do |from|
        from_user = get_user(from)
        sum += from_user.is_police ? 2 : 1
      end
      if sum > max_vote then
        max_vote = sum
        winners = [to]
      elsif sum == max_vote then
        winners.push(to)
      end
    end
  end

  def to_h
    {
      :id => @id,
      :num_players => @num_players,
      :num_werewolves => @num_werewolves,
      :night => @night,
      :cur_move => @cur_move,
      :cards => @cards,
      :votes => @votes,
      :users => @users.map{|k, v| [k, v.to_h]}.to_h,
      :werewolf_kills => @werewolf_kills,
      :witch_rescue => @witch_rescue,
      :witch_poison => @witch_poison,
      :banishes => @banishes
    }
  end
end

class User
  attr_reader :id, :card, :is_candidate, :is_couple, :is_login
  attr_accessor :is_dead, :is_police
  def self.create(id, card, room_id)
    klass = case card
    when :villager
      User
    when :seer
      Seer
    when :witch
      Witch
    when :werewolf
      Werewolf
    when :hunter
      Hunter
    else
      raise :unknown_character
    end
    klass.new(id, card, room_id)
  end

  def room
    @room = Room.get_room(@room_id) if @room.nil?
    @room
  end

  def signin
    unless @is_login
      room.user_signin(@id)
      @is_login = true
    end
    true
  end

  def can_vote
    !is_dead && !is_spirit
  end

  def can_take_action?
    !is_dead || room.get_death_night.include?(id)
  end

  def vote(to_id)
    room.vote(id, to_id)
  end

  def kill(uid)
    raise :wrong_action
  end

  def rescue
    raise :wrong_action
  end

  def no_rescue
    raise :wrong_action
  end

  def poison(uid)
    raise :wrong_action
  end

  def no_poison
    raise :wrong_action
  end    

  def check(uid)
    raise :wrong_action
  end

  def connect(uid1, uid2)
    raise :wrong_action
  end

  def shoot(uid)
    raise :wrong_action
  end

  def to_h
    {
      :id => @id,
      :card => @card,
      :room => room,
      :is_dead => @is_dead,
      :is_candidate => @is_candidate,
      :is_police => @is_police,
      :is_couple => @is_couple,
    }
  end
protected
  def initialize(id, card, room_id)
    @id = id
    @room_id = room_id
    @card = card
    @is_dead = false
    @is_candidate = false
    @is_police = false
  end
end

class Werewolf < User
  def kill(uid)
    raise :wrong_action if room.cur_move != :werewolves_kill
    room.werewolf_kill(@id, Integer(uid))
  end
end

class Seer < User
  def check(uid)
    raise :wrong_action if room.cur_move != :seer_check
    room.seer_check(id, uid)
  end
end

class Witch < User
  def rescue
    raise :wrong_action if room.cur_move != :witch_rescue
    room.witch_rescue(id)
  end

  def no_rescue
    raise :wrong_action if room.cur_move != :witch_rescue
    room.go_next_move
  end

  def poison(uid)
    raise :wrong_action if room.cur_move != :witch_poison
    room.witch_poison(id, uid)
  end

  def no_poison
    raise :wrong_action if room.cur_move != :witch_poison
    room.go_next_move
  end
end

class Cupit < User

end

class Hunter < User

end

class Idiot < User

end

#### APIS #####

#handle json post request
before do
  if request.request_method == "POST" && request.content_type.start_with?('application/json')
    body_parameters = request.body.read
    params.merge!(Yajl::Parser.parse(body_parameters))
  end
end

def get_or_post(path, opts={}, &block)
  get(path, opts, &block)
  post(path, opts, &block)
end

#TODO: change to post, get for easy testing
get_or_post '/create_room' do
  num_players = Integer(params[:num_players])
  num_werewolves = Integer(params[:num_werewolves])
  gods = []
  GODS.each do |char|
    gods.push(char) if params[char] == true || params[char] == 'true'
  end
  room = Room.new(num_players, num_werewolves, gods)
  Yajl::Encoder.encode({:room_id => room.id })
end

get '/:room_id/room_info' do
  room = Room.get_room(params[:room_id])
  halt 404, 'room not found' if room.nil?
  Yajl::Encoder.encode(room.to_h)
end

get_or_post '/:room_id/user_signin/:user_id' do
  room = Room.get_room(params[:room_id])
  user_id = Integer(params[:user_id])
  user = room.get_user(params[:user_id])
  Yajl::Encoder.encode({
    :succeed => user.signin,
    :user => user.to_h
  })
end

get '/:room_id/user_card/:user_id' do
  room = Room.get_room(params[:room_id])
  user_id = Integer(params[:user_id])
  room.cards[user_id].to_s
end

get '/:room_id/cur_move' do
  room = Room.get_room(params[:room_id])
  ret = {:cur_move => room.cur_move.to_s}
  case room.cur_move
  when :reveal_death
    ret[:death] = room.get_death_night
  when :witch_rescue
    ret[:killed] = room.witch_can_rescue? ? room.get_wolveskill_tonight : -1
  end
  # put here to keep tests working
  room.heart_beat_check
  Yajl::Encoder.encode(ret);
end

#TODO: change to post, get for easy testing
get '/:room_id/god_go_next_move' do
  room = Room.get_room(params[:room_id])
  room.go_next_move.to_s
end

#TODO: change to post, get for easy testing
get_or_post '/:room_id/take_action/:user_id' do
  room = Room.get_room(params[:room_id])
  user = room.get_user(params[:user_id])
  action = params[:action]
  target = params[:target]
  raise wrong_action if !user.can_take_action?
  case action
  when 'werewolf_kill'
    if user.card == :werewolf && !user.is_dead && (target.nil? || target == '')
      room.go_next_move  #no kill
    else
      user.kill(target)
    end
  when 'seer_check'
    Yajl::Encoder.encode({:result => user.check(target)})
  when 'witch_rescue'
    user.rescue
  when 'witch_no_rescue'
    user.no_rescue
  when 'witch_poison'
    user.poison(target)
  when 'witch_no_poison'
    user.no_poison
  end
end

#TODO: change to post, get for easy testing
# god can designate who's police, who's bunished
get_or_post '/:room_id/god_take_action' do
  room = Room.get_room(params[:room_id])
  action = params[:action]
  target = params[:target]
  if target.nil? || target == ''
    room.go_next_move
  else
    case action
    when 'select_police'
      raise :wrong_action if room.cur_move != :all_compaign_1st
      room.select_police(target)
    when 'select_banish'
      raise :wrong_action if room.cur_move != :all_speakAndBanish
      room.select_banish(target)
    end
  end
end 
