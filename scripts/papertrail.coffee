# Description:
#   Query logs from Papertrail
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_PAPERTRAIL_API_TOKEN - Papertrail API token
#
# Commands:
#   hubot log me <query> - Search logs for query
#   hubot papertrail me <query> - Search logs for query
#   hubot log me group=<group> <query> - Search logs in specific group
#   hubot papertrail me group=<group> <query> - Search logs in specific group
#   hubot log me server=<server> <query> - Search logs in specific server
#   hubot papertrail me server=<server> <query> - Search logs in specific server
#   hubot papertrail groups - List all groups
#   hubot papertrail group <group name> - Get info on group
#   hubot papertrail alias group <group name> to <alias> - Create alias for group
#   hubot papertrail remove alias <alias> from group <group name> - Remove an alias for a group
#   hubot papertrail refresh groups - Refresh group list
#
# Author:
#   eric
#

module.exports = (robot) ->
  if !process.env.HUBOT_PAPERTRAIL_API_TOKEN
    robot.logger.error "Missing HUBOT_PAPERTRAIL_API_TOKEN in environment: please set and try again"
    return
  baseUrl = "https://papertrailapp.com/api/v1/"

  http_request = (path) ->
    robot.http("#{baseUrl}#{path}")
      .headers("X-Papertrail-Token": process.env.HUBOT_PAPERTRAIL_API_TOKEN)

  class GroupAliases
    constructor: ->
      @aliases = robot.brain.data.papertrailGroupAliases ?= {}

    for: (id) ->
      @aliases[id] ||= []

    set: (id, list) ->
      if list
        @aliases[id] = list
      else
        delete @aliases[id]
      robot.brain.save()

  groupAliases = new GroupAliases

  class Group
    constructor: (@data) ->

    id: -> @data.id
    name: -> @data.name
    searchUrl: -> @data._links.search
    systemCount: -> @data.systems.length

    description: ->
      if @aliases().length > 0
        "#{@name()} (#{@aliases().join(", ")})"
      else
        @name()

    aliases: -> groupAliases.for(@id())

    setAliases: (list) -> groupAliases.set(@id(), list)

    hasAlias: (value) ->
      value = value.toLowerCase()
      for alias in @aliases()
        if alias == value
          return true
      return false

    addAlias: (value) ->
      value = value.toLowerCase()
      @aliases().push value

    removeAlias: (value) ->
      value = value.toLowerCase()
      newAliases = alias for alias in @aliases() when alias != value
      @setAliases newAliases

  class Groups
    constructor: () ->
      @groups = []
      @fetch ->
        robot.logger.info "Papertrail groups loaded"

    findById: (id) ->
      for group in @groups
        if group.id() == id
          return group
      return

    findByExactName: (name) ->
      name = name.toLowerCase()
      for group in @groups
        if group.name().toLowerCase() == name
          return group
      return

    findByAlias: (alias) ->
      alias = alias.toLowerCase()
      for group in @groups
        if group.hasAlias(alias)
          return group
      return

    findByFuzzyName: (name) ->
      name = name.toLowerCase()
      for group in @groups
        if group.name().toLowerCase().indexOf(name) != -1
          return group
      return

    find: (value, callback, dontFetch) ->
      group = null
      group ?= @findById(value)
      group ?= @findByExactName(value)
      group ?= @findByAlias(value)
      group ?= @findByFuzzyName(value)

      if group
        callback(group)
        return

      if dontFetch
        callback()
      else
        @fetch =>
          @find(value, callback, true)

    fetch: (callback) ->
      http_request("groups.json").get() (err, res, body) =>
        if res.statusCode != 200
          robot.logger.warning "Error talking to Papertrail"
          robot.logger.warning body
        else
          response = JSON.parse(body)
          @groups = for group in response
            new Group(group)

        if callback
          callback(@groups)

  class Server
    constructor: (@data) ->

    id: -> @data.id
    name: -> @data.name

  class Servers
    constructor: ->
      @servers = []
      @fetch ->
        robot.logger.info "Papertrail servers loaded"

    findById: (id) ->
      for server in @servers
        if server.id() == id
          return server
      return

    findByExactName: (name) ->
      name = name.toLowerCase()
      for server in @servers
        if server.name().toLowerCase() == name
          return server
      return

    findByFuzzyName: (name) ->
      name = name.toLowerCase()
      for server in @servers
        if server.name().toLowerCase().indexOf(name) != -1
          return server
      return

    find: (value, callback, dontFetch) ->
      server = null
      server ?= @findById(value)
      server ?= @findByExactName(value)
      server ?= @findByFuzzyName(value)

      if server?
        callback(server)
        return

      if dontFetch
        callback()
      else
        @fetch =>
          @find(value, callback, true)

    fetch: (callback) ->
      http_request("systems.json").get() (err, res, body) =>
        if res.statusCode != 200
          robot.logger.warning "Error talking to Papertrail"
          robot.logger.warning body
        else
          response = JSON.parse(body)
          @servers = for server in response
            new Server(server)

        if callback
          callback(@servers)

  # Initialize the groups
  papertrailGroups = new Groups
  papertrailServers = new Servers


  robot.respond /(?:log|papertrail) me(?: group=(?:"([^"]+)"|(\S+)))?(?: (?:server|host|system|source)=(\S+))?(?: (.*))?$/i, (msg) ->
    fetchResults = (queryOptions) ->
      if queryOptions.group_id?
        htmlUrl = "https://papertrailapp.com/groups/#{queryOptions.group_id}/events"
      else if queryOptions.system_id?
        htmlUrl = "https://papertrailapp.com/systems/#{queryOptions.system_id}/events"
      else
        htmlUrl = "https://papertrailapp.com/events"

      if queryOptions.q?
        htmlUrl += "?q=#{escape(queryOptions.q)}"

      http_request("events/search.json")
        .query(queryOptions)
        .get() (err, res, body) ->
          if res.statusCode != 200
            msg.send "Error talking to papertrail:"
            msg.send body
          else
            response = JSON.parse(body)
            events = for event in response.events
              "#{event.display_received_at} #{event.source_name} #{event.program}: #{event.message}"

            if events.length == 0
              msg.send "\"#{queryOptions.q || ""}\": No matches were found in time. Search harder at: #{htmlUrl}"
            else
              matchText = if events.length == 1 then "match" else "matches"
              msg.send "\"#{queryOptions.q || ""}\" found #{events.length} #{matchText} – #{htmlUrl}"
              msg.send events.join("\n") + "\n"

    groupName = msg.match[1] || msg.match[2]
    serverName = msg.match[3]
    query = msg.match[4]

    if groupName?
      papertrailGroups.find groupName, (group) ->
        if group?
          fetchResults(q: query, group_id: group.id())
        else
          msg.send "Could not find group \"#{groupName}\". Use \"/papertrail groups\" for possible options"
    else if serverName?
      papertrailServers.find serverName, (server) ->
        if server?
          fetchResults(q: query, system_id: server.id())
        else
          msg.send "Could not find server \"#{serverName}\". Use \"/papertrail servers\" for possible options"
    else
      fetchResults(q: query)

  robot.respond /papertrail (refresh )?groups$/i, (msg) ->
    printDescription = (groups) ->
      groupDescriptions = for group in groups
        group.description()

      msg.send "Papertrail groups:"
      msg.send groupDescriptions.join("\n") + "\n"

    if msg.match[1]
      papertrailGroups.fetch(printDescription)
    else
      printDescription(papertrailGroups.groups)

  robot.respond /papertrail (refresh )?(?:servers|sources|hosts|systems)$/i, (msg) ->
    printDescription = (servers) ->
      serverDescriptions = for server in servers
        server.name()

      msg.send "Papertrail servers:"
      msg.send serverDescriptions.join("\n") + "\n"

    if msg.match[1]
      papertrailServers.fetch(printDescription)
    else
      printDescription(papertrailServers.servers)


  robot.respond /papertrail alias group +(.*) +to (\S+)/i, (msg) ->
    groupName = msg.match[1]
    alias = msg.match[2]

    papertrailGroups.find groupName, (group) ->
      if group?
        group.addAlias(alias)
        msg.send "Added an alias of \"#{alias}\" for \"#{groupName}\""
      else
        msg.send "Could not find group #{groupName}"

  robot.respond /papertrail (?:remove|delete) alias (\S+) from group +(.*)/i, (msg) ->
    groupName = msg.match[2]
    alias = msg.match[1]

    papertrailGroups.find groupName, (group) ->
      if group?
        group.removeAlias(alias)
        msg.send "Removed an alias of \"#{alias}\" from \"#{groupName}\""
      else
        msg.send "Could not find group #{groupName}"

  robot.respond /papertrail group (.*)/i, (msg) ->
    groupName = msg.match[1]

    papertrailGroups.find groupName, (group) ->
      if group?
        msg.send "#{group.description()}"
        msg.send "Systems: #{group.systemCount()}\n"
      else
        msg.send "Could not find group #{groupName}"

  robot.respond /papertrail (?:server|source|host|system) (.*)/i, (msg) ->
    serverName = msg.match[1]

    papertrailServers.find serverName, (server) ->
      if server?
        msg.send "#{server.name()}"
      else
        msg.send "Could not find server #{serverName}"
