
assert = require "assert"
ldap = require "ldapjs"
_  = require "underscore"
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


nano = require("nano")("http://localhost:5984")
server = ldap.createServer()
usersDB = nano.db.use(config.dbName)
ldapWrap = require("./ldapwrap")(usersDB, config.orgKey)

# TODO: should be ignore on the ldap client level
ignoreUsers =
  lightdm: 1
  root: 1
  opinsys: 1
  epeli: 1

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


  if isMasterDN(req.dn)
    if req.credentials is config.localMasterPassword
      res.end()
      return next()
    else
      console.info "Bad master password"
      return next new ldap.InvalidCredentialsError

  else
    uid = req.dn.rdns[0].couchuser
    ldapWrap.validatePassword uid, req.credentials, (err, ok) ->

      if err
        console.error "Failed to validate password for #{ uid }"
        return next new ldap.OperationsError "internal error"

      if ok
        res.end()
        return next()
      else
        console.info "Bad password for #{ uid }"
        next new ldap.InvalidCredentialsError



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

