
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


isAllFilter = schema
  type: "present"
  attribute: "objectclass"


isMasterDN = schema
  rdns:
    0: ou: "Master"
    1: dc: String # Organisation key
    2: dc: "fi"
    length: 3

isGroupFilterByGIDNumber = schema
  type: "and"
  filters:
    length: 2
    0:
      type: "equal"
      attribute: "objectclass"
      value: "posixgroup"
    1:
      type: "equal"
      attribute: "gidnumber"
      value: /^[0-9]+$/

isGroupFilterByMember = schema
  type: "and"
  filters:
    length: 2
    0:
      type: "equal"
      attribute: "objectclass"
      value: "posixgroup"
    1:
      type: "or"
      filters:
        length: 2
        0:
          type: "equal"
          attribute: "memberuid"
          value: String
        1:
          type: "equal"
          attribute: "member"
          value: String

module.exports =
  isUIDFilter: isUIDFilter
  isAllFilter: isAllFilter
  isUIDNumberFilter: isUIDNumberFilter
  isMasterDN: isMasterDN
  isGroupFilterByMember: isGroupFilterByMember
  isGroupFilterByGIDNumber: isGroupFilterByGIDNumber


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


  groupFilterByGIDNumber = ldap.parseFilter "(&(objectclass=posixgroup)(gidnumber=1005))"
  assert.ok isGroupFilterByGIDNumber groupFilterByGIDNumber

  groupFilterByMember = ldap.parseFilter "(&(objectclass=posixgroup)(|(memberuid=aarlorvilehto)(member=couchuser=aarlorvilehto, ou=People, dc=kehitys, dc=fi)))"
  assert.ok isGroupFilterByMember groupFilterByMember

