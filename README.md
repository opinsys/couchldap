
# CouchLDAP

Experimental LDAP server implementation for `libpam-ldapd` and
`libnss-ldapd` written with [ldapjs][] and CouchDB.

## Setup

### CouchMaster Server

Get Node.js and Apache CouchDB 1.2

Get CouchLDAP repo

    git clone git://github.com/opinsys/couchldap.git
    cd couchldap
    npm install

Populate CouchMaster db with data

    node_modules/.bin/coffee populatemaster.coffee http://localhost:5984/

Setup puavoCouch

    cd puavocouch
    npm install
    npm start # Keep this running


### CouchLDAP Server for local organisation

Get Node.js and Apache CouchDB 1.2

Get CouchLDAP repo

    git clone git://github.com/opinsys/couchldap.git
    cd couchldap
    npm install

Create `config.json`

```json
{
    "orgKey": "kehitys"
    , "couchMaster": "couchmaster ip"
    , "couchLDAPPassword": "secret"
}
```

And start CouchLDAP

    npm start

### Desktop client setup

For Ubuntu Precise Pangolin

    sudo apt-get install libpam-ldapd libnss-ldapd nslcd ldap-utils

#### `/etc/nslcd.conf`

    # The user and group nslcd should run as.
    uid nslcd
    gid nslcd

    # CouchLDAP server
    uri ldap://couchldapserver:1389/

    # The search base that will be used for all queries.
    base dc=kehitys,dc=fi
    base group ou=Groups,dc=kehitys,dc=fi
    base passwd ou=People,dc=kehitys,dc=fi

    binddn ou=Master,dc=kehitys,dc=fi
    # Configured in config.json
    bindpw secret


[ldapjs]: http://ldapjs.org/
