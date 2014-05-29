# Description:
#   A Hubot plugin for the Rollcall service at https://gorollcall.com
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_ROLLCALL_WEBHOOK - get this URL from https://my.gorollcall.com/
#
#
# Commands:
#   rollcall i am <rollcall email address> - map your user to your Rollcall account (required!)
#   rollcall who am i - see if Rollcall knows who you are (only checks Hubot, not the server)
#   rollcall forget me - clear the mapping on server and in hubot
#   rollcall search <entity search terms e.g. owner/project#term> - search for issuses or projects for use in your status update
#   rollcall working on <status update> - update your status on Rollcall
#   rollcall post <status update> - alternative syntax for posting a status update
#   rollcall <status update> - alternative, simpler syntax for status updates
#
# URL:
#   POST /hubot/rollcall
#
# Author:
#   sujal

util = require('util')
url = require('url')
querystring = require('querystring')

send_command_to_rollcall = (msg, command, matched_data, callback) ->

  remote_username = msg.message.user.id
  rollcall_account = null
  if command == "map"
    rollcall_account = matched_data
  else
    rollcall_account = msg.message.user.rollcallAccount

  # console.log rollcall_account

  return callback(new Error("I don't know your username on Rollcall. Tell me who you are.")) unless rollcall_account?

  post_body = {
    command: command,
    from: rollcall_account,
    remote_username: remote_username
  }

  if (command != "map" or command != "unmap")
    post_body["body"] = matched_data

  # console.log post_body

  msg.http(process.env.HUBOT_ROLLCALL_WEBHOOK)
    .headers(Accept: 'application/json', "Content-Type": "application/json")
    .post(JSON.stringify(post_body)) (err, res, body) ->

      return callback(err) if err?

      r = JSON.parse(body)

      switch res.statusCode
        when 200
          switch command
            when "map"
              msg.message.user.rollcallAccount = matched_data
            when "unmap"
              msg.message.user.rollcallAccount = undefined

          return callback(null, r)
        when 404
          return callback(new Error("404 Received: #{r?.meta?.text}"), r)
        when 403
          return callback(new Error("Error: #{r?.meta?.text}"), r)
        else
          return callback(new Error("Unknown Error: #{r?.meta?.text}"), r)



module.exports = (robot) ->
  if process.env.HUBOT_ROLLCALL_WEBHOOK

    robot.hear /^(?:@|\/)?rollcall:?\s*(who\s+am|i\s+am|search|working\s+on|post|forget)?\s+(.*)$/i, (msg) ->
      # console.log "user_command is #{user_command}"

      user_command = msg.match[1]
      command_data = msg.match[2]

      user_command = user_command.toLowerCase().replace(/\s+/g, " ") if user_command?

      # console.log "user_command is #{user_command}"

      actual_command = switch user_command
        when "i am"
          "map"
        when "search"
          "search"
        when "forget"
          "unmap"
        when "who am"
          user = msg.message.user
          if user.rollcallAccount?
            msg.reply "You are known as #{user.rollcallAccount} on Rollcall"
          else
            msg.reply "I don't know who you are. Tell rollcall who you are."
          null
        else # /working\s+on/, "post", no command all are POST ME! :)
          "post"

      # console.log actual_command

      return unless actual_command?

      send_command_to_rollcall msg, actual_command, command_data, (err, response) ->
        return robot.reply "Rollcall Error: #{err.message}" if err?

        switch actual_command
          when "map"
            msg.reply "You are #{command_data} on Rollcall."
          when "search"
            output = null
            result_count = response.organization?.matching_entities?.length || 0
            if (result_count == 0)
              output = "Found 0 results for #{command_data}"
            else
              output = "Found #{result_count} results for #{command_data}:\n\n"
              for entity in response.organization.matching_entities
                output += "#{entity.name}\n"

            msg.reply output

          when "unmap"
            msg.reply "You're no longer mapped to a Rollcall account."
          when "post"
            msg.reply "✓"


    robot.router.post "/hubot/rollcall", (req, res) ->

      query = querystring.parse url.parse(req.url).query

      room=query.room

      res.end JSON.stringify {
        received: true #some client have problems with and empty response
      }

      try

        payload = req.body

        message = "[#{payload.status.organization.domain}] #{payload.status.body} - #{payload.status.user.name}"

        if payload.status.entities? and payload.status.entities.length > 0
          message += "\n"

          for entity in payload.status.entities
            message += "\n#{entity.name} - #{entity.url}"

        robot.messageRoom room, message

      catch error
        console.log "rollcall hook error: #{error}. Payload: #{req.body}"