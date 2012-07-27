
# CouchLDAP

Experimental LDAP server implementation for `libpam-ldapd` and
`libnss-ldapd` written with [ldapjs][] and CouchDB.

## Setup

This demo setup requires two servers, a master server and a slave server for a
*kehitys* organisation, and one or more desktop clients for the slave server.

### Master Server with PuavoCouch

Contains CouchDB master and PuavoCouch.

Install Node.js 0.6 and Apache CouchDB 1.2.

Get CouchLDAP repo and go to PuavoCouch subdirectory:

    git clone git://github.com/opinsys/couchldap.git
    cd couchldap/puavocouch/
    npm install

Populate CouchMaster db with data:

    npm run-script populate

Password for everybody is *kala*

Start PuavoCouch:

    npm start

### Slave Server with CouchLDAP

Contains CouchDB slave and CouchLDAP.

Install Node.js 0.6 and Apache CouchDB 1.2.

Get CouchLDAP repo

    git clone git://github.com/opinsys/couchldap.git
    cd couchldap
    npm install

Create `config.json`

```json
{
    "orgKey": "kehitys"
    , "couchMaster": "<master server ip>"
    , "couchLDAPPassword": "secret"
}
```

And start CouchLDAP

    npm start

This will automatically replicate *kehitys* organisation data from the Master
Server.

### Desktop Client Setup

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
