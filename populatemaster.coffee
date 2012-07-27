
# Tool for populating CouchDB master with some random test data.

async = require "async"
csv = require "csv"
ssha = require "ssha"

config = require "./config"

do ->
  config.dbName = "#{ config.orgKey }-users"
  config.masterCouchURL = "http://#{ config.couchMaster }:5984/#{ config.dbName }"
  config.localCouchURL = "http://localhost:5984/#{ config.dbName }"

nano = require("nano")("http://#{ config.couchMaster }:5984/")

nano.db.create(config.dbName)
kehitysUsers = nano.db.use(config.dbName)


nano.db.create("toimisto-users")
toimistoUsers = nano.db.use("toimisto-users")


q = async.queue (task, cb) ->
  task(cb)
, 5


id = 10000

usedNames = {}

console.info "Going to insert test data to #{ config.masterCouchURL }"
console.info "This might take a while..."

[kehitysUsers, toimistoUsers].forEach (db) ->
  q.push (done) ->
    db.insert
      guests: 1008
      student: 1006
      teacher: 1007
      users: 1005
    , "groups", (err, doc) ->
      if err
        console.info "Group insertion failed because", err
      done()


[
  username: "epeli"
  gender: "male"
  givenName: "Esa-Matti"
  surname: "Suuronen"
  streetAddress: null
  city: null
  zipCode: null
  email: null
  password: ssha.create("kala")
  loginShell: "/bin/bash"
  groups: [ "users", "student", "admin" ]
  id: ++id
,
  username: "employee"
  gender: "male"
  givenName: "John"
  surname: "Doe"
  streetAddress: null
  city: null
  zipCode: null
  email: null
  password: ssha.create("kala")
  loginShell: "/bin/bash"
  groups: [ "users", "student", "admin" ]
  id: ++id
].forEach (doc) -> q.push (done) ->
  toimistoUsers.insert doc, "user-#{ doc.username }", (err, doc) ->
    if err
      console.error "Failed to insert", doc, err
    done()


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

  q.push (done) ->
    kehitysUsers.insert doc, "user-#{ doc.username }", (err, doc) ->
      if err
        console.info "Failed to insert", doc, "because", err
      done()


q.drain = ->
  console.info "All done"


