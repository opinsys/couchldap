
_  = require "underscore"


# Wrapper for CouchDB nano driver which caches documents and transforms them to
# format required by ldapjs
#
# @param {nano object}
# @param {String} organisation key
# @return {LDAPWrap}
class LDAPWrap

  constructor: (@db, @orgKey) ->

    @ldapGroups = []
    @docCache = {}

    @db.follow (since: "now"), (err, response) =>
      if @docCache[response.id]
        console.info "Cached doc '#{ response.id }' updated. Clearing."
        delete @docCache[response.id]

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

  # When this is called the UID numbers should be all in the cache, because the
  # login procedure has already fetched it by UID few times. There should be
  # never a need to query these from the database.
  cachedUIDNumbertoUID: (uidNumber) ->
    uidNumber = parseInt(uidNumber, 10)

    for k, cachedDoc of @docCache
      [err, doc] = cachedDoc

      if err
        continue

      if k.slice(0,4) isnt "user"
        continue

      if parseInt(doc.id, 10) is uidNumber
        return doc.username

  getUser: (uid, pickAttrs, cb) ->

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
          gidnumber: gidNumber
          loginshell: doc.loginShell

        if pickAttrs
          attributes = _.pick(attributes, pickAttrs)

        cb null,
          dn: "couchUser=#{ doc.username },ou=People,dc=#{ @orgKey },dc=fi"
          attributes: attributes


module.exports = (args...) -> new LDAPWrap args...
