# The Werewolves Game (狼人杀) simple server

The common problem we face when playing Werewolves game is that, often it's hard to gather enough players, and 1 person has to play god, which further reduced 1 player from enjoying the game.

This is a simple web server that can run on a laptop with ruby, and connect from your cell phones to play Werewolves game, so that all the players can enjoy the game itself.

This server is still under development

# How to Run

## First Time
1. install rvm with ruby 2.1.5 from https://rvm.io/
2. install bundler by run
   $ gem install bundler
3. $ bundle install

## Start the server
$ ruby server.rb

## Test command
create a room
http://localhost:4567/create_room?num_players=11&num_wolves=4&prophet=true&witch=true&cupit=true&idiot=true

see the room info
http://localhost:4567/0/room_info

see player card
http://localhost:4567/0/user_card/2