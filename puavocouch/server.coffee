
express = require "express"
ssha = require "ssha"

nano = require("nano")("http://localhost:5984")

app = express.createServer()


# user@organisation style basic auth parser for Connect
parseBasicAuth = (req, res, next) ->

  if match = req.headers.authorization?.match(/^Basic (.+)$/)
    credentials = new Buffer(match[1], "base64").toString()
    [username, password] = credentials.split(":")
    [uid, organisation] = username.split("@")
    req.user =
      username: username
      password: password
      uid: uid
      organisation: organisation
  next()

# Validate user
requireAuth = (req, res, next) ->
  if not req.user
    return res.json (error: "basic auth missing"), 401

  console.info "user", req.user
  db = nano.use(req.user.organisation + "-users")
  db.get "user-" + req.user.uid, (err, doc) ->
    if err
      console.error "Failed to fetch", req.user, err
      return res.json (error: "failed to find user #{ req.user.uid } from #{ req.user.organisation }"), 501

    if not ssha.verify(req.user.password, doc.password)
      return res.json (error: "bad username or password"), 401

    req.user.data = doc
    next()


app.use(parseBasicAuth)


# Private user data end point
#
# @return {Object} user data
app.get "/whoami", requireAuth, (req, res) ->
  res.json req.user.data


# Public UID number query API
#
# @query {String:uid}
# @query {String:organisation}
# @return {Number} UID number for uid
app.get "/uidnumber", (req, res) ->
  console.info "UID number query", req.query

  db = nano.use(req.query.organisation + "-users")
  db.get "user-" + req.query.uid, (err, doc) ->
    if err
      res.json err, 404
    else
      res.json doc.id


app.listen 1234, -> console.info "Puavo listening on 1234"
