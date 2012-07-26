
assert = require "assert"
ldap = require "ldapjs"
_  = require "underscore"
require "colors"


{ isUIDFilter
  isAllFilter
  isUIDNumberFilter
  isGroupFilterByMember
  isGroupFilterByGIDNumber
  isGuestDN
  isMasterDN } = require "./ldapmatchers"


config = require "./config"
do ->
  config.dbName = "#{ config.orgKey }-users"
  config.masterCouchURL = "http://#{ config.couchMaster }:5984/#{ config.dbName }"
  config.localCouchURL = "http://localhost:5984/#{ config.dbName }"


nano = require("nano")("http://localhost:5984")
server = ldap.createServer()
usersDB = nano.db.use(config.dbName)
ldapWrap = require("./ldapwrap")(usersDB, config.orgKey, config.puavo)

# TODO: should be ignore on the ldap client level
ignoreUsers =
  lightdm: 1
  root: 1
  opinsys: 1
  epeli: 1



# master ie. local organisation desktop/client master
loginMaster = (req, res, next) ->
  if req.credentials is config.localMasterPassword
    res.end()
    return next()
  else
    console.info "Bad master password"
    return next new ldap.InvalidCredentialsError



# Guest user from another organisation
loginGuest = (req, res, next) ->
  guest = req.dn.rdns[0].couchuser
  console.info "Logging in guest!", guest, req.credentials

  ldapWrap.remoteLogin guest, req.credentials, (err, ok) ->
    if err
      console.error "Failed to login remote guest #{ guest }", err
      return next ldap.OperationsError "internal error"

    if ok
      res.end()
      next()
    else
      return next ldap.InvalidCredentialsError


# Local user. Student, teacher, etc.
loginLocalUser = (req, res, next) ->
  uid = req.dn.rdns[0].couchuser

  ldapWrap.validatePassword uid, req.credentials, (err, ok) ->
    if err
      console.error "Failed to validate password for #{ uid }", req.dn.toString()
      return next new ldap.OperationsError "internal error"

    if ok
      res.end()
      return next()
    else
      console.info "Bad password for #{ uid }"
      next new ldap.InvalidCredentialsError

server.bind "dc=#{ config.orgKey },dc=fi", (req, res, next) ->


  if isMasterDN(req.dn)
    return loginMaster(req, res, next)
  else if isGuestDN(req.dn)
    return loginGuest(req, res, next)
  else
    return loginLocalUser(req, res, next)




sendUserByUID = (uid, req, res) ->

  if not uid
    throw new Error "null uid"

  if ignoreUsers[uid]
    return res.end()

  ldapWrap.getUser uid, req.attributes, (err, user) ->
    if err
      console.info "Failed to fetch #{ uid }".red, err
    else
      res.send(user)
    res.end()


sendUserByUIDNumber = (uidNumber, req, res) ->

  if uid = ldapWrap.cachedUIDNumbertoUID(uidNumber)
    sendUserByUID(uid, req, res)
  else
    console.error "Could not find uid for number #{ uidNumber }".red
    res.end()


# Send user owning this connection
sendSelf = (req, res) ->
  dn = res.connection.ldap.bindDN
  uid = dn.rdns[0].couchuser
  sendUserByUID(uid, res, res)


server.search "ou=People,dc=#{ config.orgKey },dc=fi", (req, res, next) ->

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





server.search "ou=Groups,dc=#{ config.orgKey },dc=fi", (req, res, next) ->

  for groupDoc in ldapWrap.groups
    if req.filter.matches(groupDoc.attributes)
      res.send(groupDoc)
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

