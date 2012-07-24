
schema = require "js-schema"



isUIDFilter = schema
  type: "and"
  filters:
    length: 2
    0:
      type: "equal"
      attribute: "objectclass"
      value: "posixaccount"
    1:
      type: "equal"
      attribute: "uid"
      value: String

isUIDFilter.getValue = (filter) ->
  filter.filters[1].value

isUIDNumberFilter = schema
  type: "and"
  filters:
    length: 2
    0:
      type: "equal"
      attribute: "objectclass"
      value: "posixaccount"
    1:
      type: "equal"
      attribute: "uidnumber"
      value: String

isUIDNumberFilter.getValue = (filter) ->
  parseInt filter.filters[1].value, 10

isAllFilter = schema
  type: "present"
  attribute: "objectclass"


isMasterDN = schema
  rdns:
    0: ou: "Master"
    1: dc: String # Organisation key
    2: dc: "fi"
    length: 3



module.exports =
  isUIDFilter: isUIDFilter
  isAllFilter: isAllFilter
  isUIDNumberFilter: isUIDNumberFilter
  isMasterDN: isMasterDN


if require.main is module
  assert = require "assert"

  ldap = require "ldapjs"

  uidFilter = ldap.parseFilter "(&(objectclass=posixaccount)(uid=epeli))"
  uidNumberFilter = ldap.parseFilter "(&(objectclass=posixaccount)(uidnumber=11542))"


  assert.ok isUIDFilter uidFilter
  assert.ok isUIDNumberFilter uidNumberFilter

  assert.ok not isUIDFilter uidNumberFilter
  assert.ok not isUIDNumberFilter uidFilter


  allFilter = ldap.parseFilter "(objectclass=*)"
  assert.ok isAllFilter allFilter

  masterDN = ldap.parseDN 'ou=Master, dc=kehitys, dc=fi'
  assert.ok isMasterDN masterDN

