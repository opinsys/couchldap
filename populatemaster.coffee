

csv = require "csv"
config = require "./config"
ssha = require "ssha"
console.info ssha

do ->
  config.dbName = "#{ config.orgKey }-users"
  config.masterCouchURL = "http://#{ config.couchMaster }:5984/#{ config.dbName }"
  config.localCouchURL = "http://localhost:5984/#{ config.dbName }"

nano = require("nano")("http://#{ config.couchMaster }:5984/")
nano.db.create(config.dbName)
masterCouch = nano.db.use(config.dbName)

id = 10000

usedNames = {}

console.info "Going to insert test data to #{ config.masterCouchURL }"
console.info "This might take a while..."

masterCouch.insert
  student: 1006
  teacher: 1007
  users: 1005
, "groups", (err, doc) ->
  if err
    console.info "Group insertion failed because", err

csv().fromPath(__dirname + "/testdata.csv").on "data", (row) ->
  doc =
    gender: row[0]
    givenName: row[1]
    surname: row[2]
    streetAddress: row[3]
    city: row[4]
    zipCode: row[5]
    email: row[6]
    password: ssha.create("kala")
    loginShell: "/bin/bash"
    groups: [ "users", "student" ]
    id: ++id

  i = 0
  prop = doc.givenName + "." + doc.surname
  prop = prop.replace(/[^a-z]/g, "")
  username = prop
  while usedNames[username]
    username = prop + (++i)

  usedNames[username] = true
  doc.username = username

  masterCouch.insert doc, "user-#{ doc.username }", (err, doc) ->
    if err
      console.info "Failed to insert", doc, "because", err




