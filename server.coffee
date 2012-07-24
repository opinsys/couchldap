
assert = require "assert"
ldap = require "ldapjs"
_  = require "underscore"
nano = require("nano")("http://localhost:5984")
clone = require "clone"
require "colors"

{ isUIDFilter
  isAllFilter
  isUIDNumberFilter
  isGroupFilterByMember
  isGroupFilterByGIDNumber
  isMasterDN } = require "./ldapmatchers"

isGuestUID = (uid) ->
  !! uid.match /.+@.+/

config = require "./config"
do ->
  config.dbName = "#{ config.orgKey }-users"
  config.masterCouchURL = "http://#{ config.couchMaster }:5984/#{ config.dbName }"
  config.localCouchURL = "http://localhost:5984/#{ config.dbName }"


server = ldap.createServer()

usersDB = nano.db.use config.dbName

# TODO: should be ignore on the ldap client level
ignoreUsers =
  lightdm: 1
  root: 1
  opinsys: 1
  epeli: 1


docCache = {}
cachedGroups = []
organisationGuests = {}

usersDB.follow (since: "now"), (err, response) ->
  if docCache[response.id]
    console.info "Cached doc '#{ response.id }' updated. Clearing."
    delete docCache[response.id]


cachedFetch = (docID, cb) ->

  if cachedDoc = docCache[docID]
    [err, doc] = cachedDoc
    return cb(err, doc)

  console.info "Fetching doc '#{ docID }' from Couch".green

  usersDB.get docID, (err, doc) ->
    docCache[docID] = [err, doc]
    buildCachedGroups()
    if err
      console.error "Failed to fetch doc '#{ docID }'".red, err
    cb(err, doc)

getGroups = (cb) -> cachedFetch "groups", cb

getLDAPUser = (uid, pickAttrs, cb) ->
  assert.equal(arguments.length, 3,
    "Bad argument count for getLDAPUser")

  cachedFetch "user-#{ uid }", (err, doc) ->
    return cb err if err

    getGroups (err, groupMap) ->
      return cb err if err

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
        dn: "couchUser=#{ doc.username },ou=People,dc=#{ config.orgKey },dc=fi"
        attributes: attributes


buildCachedGroups = ->

  cachedGroups = []

  if not docCache["groups"] then return

  [err, cachedGroups] = docCache["groups"]

  if err then return

  for group, gidNumber of cachedGroups

    ldapGroupDoc =
      dn: "cn=#{ group },ou=Groups,dc=#{ config.orgKey },dc=fi"
      attributes:
        objectclass: "posixgroup"
        displayname: group
        cn: group
        gidnumber: "" + gidNumber
        memberuid: []

    for k, cacheDoc of docCache when k.slice(0,4) is "user"
      [err, doc] = cacheDoc
      if err then continue

      for userGroup in doc.groups
        if userGroup is group
          ldapGroupDoc.attributes.memberuid.push(doc.username)

    cachedGroups.push(ldapGroupDoc)
    return cachedGroups




getGuestData = (uid, orgKey, password, cb) ->
  if res = organisationGuests[uidWithOrg]
    return cb res...

  # Fetch user data from remote organisation with the password
  if password
    # TODO
  else
    # Respond with a dummy account (/bin/false) until we have proper data
    cb null,
      dn: "couchUser=#{ uid },ou=People,dc=#{ orgKey },dc=fi"
      attributes:
        objectclass: "posixaccount"
        cn: "Guest #{ uid } from #{ orgKey }"
        uid: uid
        givenName: "Guest #{ uid } from #{ orgKey }"
        sn: "Guest #{ uid } from #{ orgKey }"
        uidnumber: "11542"
        displayName: "Guest #{ uid } from #{ orgKey }"
        homeDirectory: "/home/guests/#{ uid }-#{ orgKey }"
        gidnumber: "1005"
        loginShell: "/bin/false"


server.bind "dc=#{ config.orgKey },dc=fi", (req, res, next) ->
  # if req.dn.toString() isnt 'cn=root' or req.credentials isnt 'secret'
  #   console.error "BAD", req.dn.toString(), req.credentials
  #   return next new ldap.InvalidCredentialsError

  # if req.dn.toString() is 'cn=root'
  #   console.info "DENY ROOT"
  #   return next new ldap.InvalidCredentialsError

  console.info "NEW LOGIN", "Login: #{ req.dn.toString() } PASS: #{ req.credentials }"



  # if req.dn.rdns[0].ou is "Master"
  #   console.info "deny master"
  #   return next new ldap.InvalidCredentialsError

  res.end()
  next()






sendUserByUID = (uid, req, res) ->

  if not uid
    throw new Error "null uid"

  if ignoreUsers[uid]
    return res.end()

  getLDAPUser uid, req.attributes, (err, user) ->
    if err
      console.info "Failed to fetch #{ uid }".red, err
    else
      res.send(user)
    res.end()


sendUserByUIDNumber = (uidNumber, req, res) ->

  uidNumber = parseInt(uidNumber, 10)
  found = false

  # At this point UID numbers should be all in the cache, because the login
  # procedure has already fetched it by UID few times. There should be never a
  # need to query these from the database.
  for k, cachedDoc of docCache
    [err, doc] = cachedDoc

    if err
      continue

    if k.slice(0,4) isnt "user"
      continue

    if parseInt(doc.id, 10) is uidNumber
      found = true
      sendUserByUID(doc.username, req, res)
      break

  if not found
    console.error "Could not find user for UID number '#{ uidNumber }'".red
    res.end()

sendSelf = (req, res) ->
  dn = res.connection.ldap.bindDN
  uid = dn.rdns[0].couchuser
  sendUserByUID(uid, res, res)


server.search "ou=People,dc=#{ config.orgKey },dc=fi", (req, res, next) ->
  # console.info "----People Search by", res.connection.ldap.bindDN.toString()
  # console.info "Base", req.baseObject.toString()
  # console.info "Filter", req.filter.toString(), "Attributes", req.attributes
  # console.info "Filter", req.filter.toString()

  bindDN = res.connection.ldap.bindDN

  if isUIDFilter(req.filter) and isMasterDN(bindDN)
    sendUserByUID(req.filter.filters[1].value, req, res)

  else if isUIDNumberFilter(req.filter) and isMasterDN(bindDN)
    sendUserByUIDNumber(
      parseInt(req.filter.filters[1].value, 10),
      req,
      res
    )

  else if isAllFilter(req.filter) and not isMasterDN(bindDN)
    sendSelf(req, res)

  else
    next()


groups = [
  {
    dn: "cn=epeli,ou=Groups,dc=#{ config.orgKey },dc=fi"
    attributes:
      objectclass: "posixgroup"
      displayname: "couchldapepeli"
      cn: "couchldap"
      gidnumber: "1005"
      memberuid: "epeli"
  }
  {
    dn: "cn=Funny Guys,ou=Groups,dc=#{ config.orgKey },dc=fi"
    attributes:
      objectclass: "posixgroup"
      displayname: "Funny Guys"
      cn: "funny"
      gidnumber: "513"
      memberuid: [
        "epeli"
        "randomguy"
      ]
  }

]





server.search "ou=Groups,dc=#{ config.orgKey },dc=fi", (req, res, next) ->
  # console.info "------Groups Search by", res.connection.ldap.bindDN.toString()
  # console.info "Base", req.baseObject.toString()
  # console.info "GROUP Filter", req.filter.toString(), "Attributes", req.attributes

  for ldapGropDoc in cachedGroups
    if req.filter.matches(ldapGropDoc.attributes)
      res.send(ldapGropDoc)

  res.end()

server.search "dc=fi", (req, res, next) ->
  console.error "----Unhandled SEARCH by".red, res.connection.ldap.bindDN.toString()
  console.error "Base".red, req.baseObject.toString()
  console.error "Filter".red, req.filter.toString()
  console.error "Attributes".red, req.attributes
  res.end()


server.modify "dc=fi", (req, res, next) ->
  console.error "----Unhandled MODIFY by".red, res.connection.ldap.bindDN.toString()
  console.error "Base".red, req.baseObject.toString()
  console.error "Changes".red, req.changes
  res.end()

server.del "dc=fi", (req, res, next) ->
  console.error "----Unhandled DEL by".red, res.connection.ldap.bindDN.toString()
  console.error "Base".red, req.baseObject.toString()
  console.error "Entry".red, req.entry
  res.end()


server.compare "dc=fi", (req, res, next) ->
  console.error "----Unhandled COMPARE by".red, res.connection.ldap.bindDN.toString()
  console.error "Base".red, req.baseObject.toString()
  console.error "com".red, req.attribute, req.value
  res.end()


server.modifyDN "dc=fi", (req, res, next) ->
  console.error "----Unhandled modifyDN by".red, res.connection.ldap.bindDN.toString()
  console.error "Base".red, req.baseObject.toString()
  console.error "com".red, req.deleteOldRdn, "->", req.newRdn
  res.end()

server.listen 1389, ->
  console.log 'CouchLDAP server up at: %s', server.url


console.info "Going to replicate changes from #{ config.masterCouchURL } to #{ config.localCouchURL }"
nano.db.replicate(
  config.masterCouchURL,
  config.localCouchURL,
  continuous: true,
  (err, response) ->
    console.info "Replication setup", err, response
)

