

# http://www.openldap.org/faq/data/cache/347.html


`
// Backport from Node.js 0.8
concat = function(list, length) {
  if (!Array.isArray(list)) {
    throw new Error('Usage: Buffer.concat(list, [length])');
  }

  if (list.length === 0) {
    return new Buffer(0);
  } else if (list.length === 1) {
    return list[0];
  }

  if (typeof length !== 'number') {
    length = 0;
    for (var i = 0; i < list.length; i++) {
      var buf = list[i];
      length += buf.length;
    }
  }

  var buffer = new Buffer(length);
  var pos = 0;
  for (var i = 0; i < list.length; i++) {
    var buf = list[i];
    buf.copy(buffer, pos);
    pos += buf.length;
  }
  return buffer;
};
`

crypto = require "crypto"

# @param {String} secret string
# @param {Buffer} Predefined salt buffer (optional)
# @return {String} salted string hash
create = (secret, salt) ->

  salt ?= crypto.randomBytes(32)

  secret = new Buffer secret

  hash = crypto.createHash("sha1")
  hash.update(secret)
  hash.update(salt)

  digest = new Buffer(hash.digest("base64"), "base64")

  buf = concat [ digest, salt ]

  return "{SSHA}" + buf.toString("base64")

# @param {String} secret string
# @param {String} salted string hash
# @return {Boolean}
verify = (secret, ssha) ->

  # Skip "{SSHA}" string
  base64 = ssha.slice(6)

  buf = new Buffer(base64, "base64")

  # Skip SHA1 hash and get the salt
  salt = buf.slice(20)

  return create(secret, salt) is ssha


module.exports =
  create: create
  verify: verify

if require.main is module
  assert = require "assert"
  ssha = create("foobar")

  console.info "HASH", ssha
  assert verify("foobar", ssha)

