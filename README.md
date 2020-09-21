# ksqldb-migrate-cli
Commandline tool for running ksqlDB schema migrations

## Motivation

Once you start playing around with ksqlDB a bit more seriously you recognize that keeping track of your changes to the database are becoming somewhat cluttered. Moreover, the task of keeping different development environments in sync becomes harder over time. 

That's what *ksqldb-migrate* takes care of: providing a tool to reproducible applying changes to a ksqldb. 

*ksqldb-migrate* basically provides you with two main functions: *update* and *rollback*. By using *update* you apply schema migrations to a ksqldb. The *rollback* reverts the changes. Read below for a more detailed description. 


## A WARNING

This tool is currently in prototype state. You will discover flaws, bugs, incompatiblities, and all kinds of things which aren't work as you potentially imagined.

See below for a list of known issues. 

## Setup

### Supported OSs

- linux

### Tool Dependencies

- bash
- curl
- find
- jq
- perl
- readlink
- sha256sum
- yq

### Installation

- download, clone, or fork the code

Run the following at the installation base folder to verify the base setup

    > ./files/usr/local/bin/ksql-migrate help

## Environment Setup

Migration files are at the heart of the migration process. Here, you describe the statements, their order, and potential rollback statements. Migration files are organized in folders. Each folder should contain all migrations for a specific schema, or functional subdomain of your (ksqldb-) application. Each migration file then will be applied during an  *update* following their alphabetical order. 

Example folder:
```
./migrations
  |-- /schema_a
  |     |-- 0001.create_first_stream.yml
  |     |-- 0002.create_first_table.yml
  |     ...
  |-- /another_schema
```
As you can see there are two schemas. *ksqldb-migrate update/rollback* expect you to name such a schema folder as argument and then apply/rollback the migration files based on alphabetical/reverse order.

    > ./files/usr/local/bin/ksql-migrate update <MIGRATIONS_ROOT>/schema_a

## Migration File Structure

A migration file is a YAML file with a distinct structure:
```
ksql:                                # required, the (multiline) ksql statement to execute
    <KSQL statement>;
streamsProperties:                   # required, the potentially empty map of properties for executing the ksql statement
    <propertyKey>: <propertyValue>   # optional, simple key-value pairs
    ...
rollback:                            # required, the rollback section 
    ksql:                            # required, the potentially empty rollback ksql statement
        <KSQL statement>;
    streamsProperties:               # required, the potentially empty map of properties for executing the rollback ksql statement
    <propertyKey>: <propertyValue>   # optional, simple key-value pairs
    ...
    
```

Example:
```
ksql:
    CREATE STREAM mystream (
        id VARCHAR KEY,
        somevalue VARCHAR
    ) WITH (
        kafka_topic = 'mytopic'
    );
streamsProperties:
rollback:
    ksql:
        DROP STREAM mystream;
    streamsProperties:
    
```

## Migration History

*ksql-migrate* keeps a history of applied migrations within ksqlDB, so that subsequent calls to *ksql-migrate update* can evaluate which migration had been already rolled. 

For each migration file *ksqldb-migrate* will build a Migration ID. The Migration ID is derived from the schema (the path) and the file name. For instance, the first migration file from the folder example at *Environment Setup* will have the Migration ID 'schema_a/0001.create_first_stream'.

Now, each migration will be registered at the migration history use a hash of its statement and properties. Consequently, if you change the contents of an already applied migration all subsequent migration runs will fail. This ensures that the migrations haven't been changed during migration runs. 

Of course, once a migration was rolled back, you can change the migration contents. Actually, the rollback section is not part of the hash so that you can change it even after the migration has been applied. 


## Known Issues

TODO, there's a alot ;)

### Rollback fails for streams, tables created by CREATE ... AS SELECT ...
Common case as the underlying query hasn't been terminated yet. There's a [ticket](https://github.com/confluentinc/ksql/issues/2177 "DROP [STREAM|TABLE] should support termination of query started during creation." ) in ksql solving this in ksql.

**Workaround**: Inspect the error to find the blocking query and TERMINATE that one manually. Then, re-run the rollback.

### Migration files with proper YAML comments get flagged as invalid YAML
Some issue in 'yq', haven't found out the reason yet (Linux Mint). If you verify the file manually with 'yq v FILE' you'll get the same error. 

**Workaround**: Don't use comments.


