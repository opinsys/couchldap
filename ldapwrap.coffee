
_  = require "underscore"
request = require "request"
ssha = require "ssha"

isGuestUID = (uid) -> !! uid.match /.+@.+/

# Wrapper for CouchDB nano driver which caches documents and transforms them to
# format required by ldapjs
#
# @param {nano object}
# @param {String} organisation key
# @return {LDAPWrap}
class LDAPWrap

  constructor: (@db, @orgKey, @puavo) ->

    @groups = []
    @ldapGroups = []
    @docCache = {}

    # TODO: Invalidate at some point
    @guestUIDNumberCache = {}


  # Start following changes from master. 
  #
  # @api public
  follow: ->
    @db.follow (since: "now"), (err, response) =>
      if err
        console.error "Change monitor failed!", err
      else if @docCache[response.id]
        console.info "Cached doc '#{ response.id }' updated. Clearing."
        delete @docCache[response.id]

  # Get cached guest data or temp dummy user. Dummy user is served until the
  # user has logged in once using a valid uid and password with `remoteLogin`.
  #
  # @api public
  # @param {String} uid@organisation
  # @param {Function} callback(err, guest)
  getCachedGuest: (guest, cb) ->

    if not @docCache["guest/" + guest]
      return @createDummyAccount guest, cb

    [__, doc] = @docCache["guest/" + guest]
    return cb null,
      dn: @guestToDN(guest)
      attributes:
        objectclass: "posixaccount"
        cn: "#{ doc.givenName } #{ doc.surname }"
        uid: guest
        givenname: doc.givenName
        sn: doc.surname
        uidnumber: "" + doc.id
        displayname: "#{ doc.givenName } #{ doc.surname }"
        homedirectory: "/home/guests/#{ doc.username }"
        gidnumber: "1005" # XXX defaults to users group
        loginshell: doc.loginShell

  # Do remote to login to another organisation with the user's uid and
  # password. This makes the user data available as read only without password.
  # This is required because libpam-ldapd or libnss-ldapd wants to access that
  # data before user actually enters password.
  #
  # @api public
  # @param {String} guestUID@organisation
  # @param {String/null} user password
  remoteLogin: (guest, password, cb) ->

    console.info "Doing remote loging for #{ guest }".green
    # Login in to PuavoCouch to get user data
    request
      uri: @puavo + "/whoami"
      basicAuth: [ guest, password ]
    , (err, res, body) =>
      if err
        console.info "Remote login failed for", guest, password
        return cb err

      if res.statusCode is 401
        return cb null, false

      user = JSON.parse(body)

      # TODO: remote groups
      # For now just support group users for remote users
      user.groups = [ "users" ]

      # Override username with guest style uid (uid@org)
      user.username = guest

      # Inject remote guest user to our cache
      @docCache["guest/" + guest] = [null, user]

      cb null, user

  # @api private
  # @param {String} uid@org
  # @return {String} DN
  guestToDN: (guest) ->
    "couchUser=#{ guest },ou=People,dc=#{ @orgKey },dc=fi"

  # Get temporary dummy account for guest user
  #
  # @api private
  # @param {String} guestUID@organisation
  # @param {Function} callback(err, dummyAccount)
  createDummyAccount: (guest, cb) ->
    @fetchGuestUIDNumber guest, (err, uidNumber) =>
      return cb err if err

      [uid, organisation] = guest.split("@")
      name = "Guest #{ uid } from #{ organisation }"

      console.info "Creating dummy account for #{ guest }"

      return cb null,
        dn: @guestToDN(guest)
        attributes:
          objectclass: "posixaccount"
          cn: name
          uid: guest
          givenName: name
          sn: name
          uidnumber: "" + uidNumber
          displayName: name
          homeDirectory: "/home/guests/#{ uid }-#{ organisation }"
          gidnumber: "1005"
          # Do not allow login with this
          loginShell: "/bin/false"
          # loginShell: "/usr/bin/python" # for testing

  # @api private
  # @param {String} guestUID@organisation
  # @param {Function} callback(err, uidNumber)
  fetchGuestUIDNumber: (guest, cb) ->

    if uidNumber = @guestUIDNumberCache[guest]
      return cb null, uidNumber

    [uid, organisation] = guest.split("@")

    request
      uri: @puavo + "/uidnumber"
      qs:
        uid: uid
        organisation: organisation
    , (err, res, body) =>
      return cb err if err
      uidNumber = @guestUIDNumberCache[guest] = parseInt(body, 10)
      console.info "Requested remote UID number #{ uidNumber } for #{ guest }".green
      cb null, uidNumber

  # Build cached view of groups for ldapjs
  # @api private
  buildLdapGroups:  ->

    if not @docCache["groups"] then return

    [err, groups] = @docCache["groups"]

    if err then return

    ldapGroups = []

    for group, gidNumber of groups

      if group[0] is "_" then continue

      ldapGroupDoc =
        dn: "cn=#{ group },ou=Groups,dc=#{ @orgKey },dc=fi"
        attributes:
          objectclass: "posixgroup"
          displayname: group
          cn: group
          gidnumber: "" + gidNumber
          memberuid: []

      for k, cacheDoc of @docCache when k.slice(0,4) is "user"
        [err, doc] = cacheDoc
        if err then continue

        for userGroup in doc.groups
          if userGroup is group
            ldapGroupDoc.attributes.memberuid.push(doc.username)

      ldapGroups.push(ldapGroupDoc)

    @groups = ldapGroups

  # @api private
  # @param {String} CouchDB document id
  # @param {Function} callback(err, doc)
  cachedFetch: (docID, cb) ->

    if cachedDoc = @docCache[docID]
      [err, doc] = cachedDoc
      return cb(err, doc)

    console.info "Fetching doc '#{ docID }' from Couch".green

    @db.get docID, (err, doc) =>

      @docCache[docID] = [err, doc]

      if err
        console.error "Failed to fetch doc '#{ docID }'".red, err
      cb(err, doc)


  # @api public
  # @param {String} uid
  # @param {String} password
  # @param {Function} callback(err, ok)
  validatePassword: (uid, password, cb) ->
    @cachedFetch "user-" + uid, (err, doc) ->
      return cb err if err
      cb null, ssha.verify(password, doc.password)


  # When this is called the UID numbers should be all in the cache, because the
  # login procedure has already fetched it by UID few times. There should be
  # never a need to query these from the database.
  #
  # @api public
  # @param {String} uid
  # @param {Number} UID Number
  # @return {String} UID
  cachedUIDNumbertoUID: (uidNumber) ->
    uidNumber = parseInt(uidNumber, 10)


    for k, cachedDoc of @docCache
      [err, doc] = cachedDoc

      if err
        continue

      if k.slice(0,4) isnt "user" and k.slice(0,5) isnt "guest"
        continue

      if parseInt(doc.id, 10) is uidNumber
        return doc.username

    console.error "Coucl not fidasdf", uidNumber
    return null

  # @api public
  # @param {String} uid
  # @param {Array} list of attributes
  # @param {Function} callback(err, user)
  getUser: (uid, pickAttrs, cb) ->

    if isGuestUID(uid)
      return @getCachedGuest uid, cb

    @cachedFetch "user-#{ uid }", (err, doc) =>
      return cb err if err

      @cachedFetch "groups", (err, groupMap) =>
        return cb err if err

        @buildLdapGroups()

        for group in doc.groups
          if not groupMap[group]
            console.error "User #{ doc.username } has invalid group #{ group }".red


        primaryGroup = doc.groups[0]
        gidNumber = groupMap[primaryGroup]
        if not gidNumber?
          return cb new Error "Cannot find gidNumber for group #{ primaryGroup }"


        attributes =
          objectclass: "posixaccount"
          cn: "#{ doc.givenName } #{ doc.surname }"
          uid: doc.username
          givenname: doc.givenName
          sn: doc.surname
          uidnumber: "" + doc.id
          displayname: "#{ doc.givenName } #{ doc.surname }"
          homedirectory: "/home/couchldap/#{ doc.username }"
          gidnumber: "" + gidNumber
          loginshell: doc.loginShell

        if pickAttrs
          attributes = _.pick(attributes, pickAttrs)

        cb null,
          dn: "couchUser=#{ doc.username },ou=People,dc=#{ @orgKey },dc=fi"
          attributes: attributes



module.exports = (args...) -> new LDAPWrap args...
