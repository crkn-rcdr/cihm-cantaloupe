# cihm-cantaloupe

`cihm-cantaloupe` is Canadiana's [Cantaloupe](https://medusa-project.github.io/cantaloupe/) configuration.

## configuration

`cihm-cantaloupe`'s configuration expects `config.json` to exist in the root directory of this repository, with the following properties set:

      {
        "repositoryBase": "/path/to/repositories"
        "secrets": {"key": "secret"}
      }

## Usage

      $ docker-compose up --build

Sets up an instance of Cantaloupe on localhost, port 8182. Note that environment variable VERSION allows you to set the version of Cantaloupe you wish to install.
