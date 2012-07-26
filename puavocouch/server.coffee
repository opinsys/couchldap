
express = require "express"
ssha = require "ssha"

# XXX
config = require "../config"


nano = require("nano")("http://#{ config.couchMaster }:5984")
nano.use(config.orgKey)

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
app.use(requireAuth)


app.get "/whoami", (req, res) ->
  res.json req.user.data

app.listen 1234
