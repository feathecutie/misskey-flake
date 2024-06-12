{ config
, pkgs
, lib
, ...
}:

let
  cfg = config.services.misskey;
  settingsFormat = pkgs.formats.yaml { };
in

{
  options = {
    services.misskey = {
      enable = lib.mkEnableOption "misskey";
      package = lib.mkPackageOption pkgs "misskey" { };
      settings = lib.mkOption {
        type = settingsFormat.type;
        default = {
          url = "https://example.tld/";
          port = 3000;
          db = {
            host = "localhost";
            port = 5432;
            db = "misskey";
            user = "example-misskey-user";
            pass = "example-misskey-pass";
          };
          dbReplications = false;
          redis = {
            host = "localhost";
            port = 6379;
          };
          id = "aidx";
          proxyBypassHosts = [
            "api.deepl.com"
            "api-free.deepl.com"
            "www.recaptcha.net"
            "hcaptcha.com"
            "challenges.cloudflare.com"
          ];
          proxyRemoteFiles = true;
          signToActivityPubGet = true;
        };
        description = ''
          Configuration for Misskey, see
          [`example.yml`](https://github.com/misskey-dev/misskey/blob/develop/.config/example.yml)
          for supported settings.
        '';
      };
      database = {
        createLocally = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Create the PostgreSQL database locally. Overrides `settings.db.{db,host,port,user,pass}`.";
        };
      };
      redis = {
        createLocally = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Create and use a local Redis instance. Overrides `settings.redis.host`";
        };
      };
      meilisearch = {
        createLocally = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Create and use a local Meilisearch instance. Overrides `settings.meilisearch.{host,port,ssl}`";
        };
      };
      reverseProxy = {
        enable = lib.mkEnableOption "a HTTP reverse proxy for Misskey";
        webserver = lib.mkOption {
          type = lib.types.attrTag {
            nginx = lib.mkOption {
              # This import only works in nixpkgs
              # type = lib.types.submodule (import ../web-servers/nginx/vhost-options.nix);
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = ''
                Extra configuration for the nginx virtual host of Misskey.
                Set to `{ }` to use the default configuration.
              '';
            };
            caddy = lib.mkOption {
              # This import only works in nixpkgs
              # type = lib.types.submodule (import ../web-servers/caddy/vhost-options.nix { cfg = config.services.caddy; });
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = ''
                Extra configuration for the caddy virtual host of Misskey.
                Set to `{ }` to use the default configuration.
              '';
            };
          };
          description = "The webserver to use as the reverse proxy.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.misskey = {
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        MISSKEY_CONFIG_YML = settingsFormat.generate "misskey-config.yml"
          (
            lib.recursiveUpdate cfg.settings
              ({
                db = lib.optionalAttrs cfg.database.createLocally {
                  db = "misskey";
                  # Use unix socket instead of localhost to allow PostgreSQL peer authentication,
                  # required for `services.postgresql.ensureUsers`
                  host = "/var/run/postgresql";
                  port = config.services.postgresql.settings.port;
                  user = "misskey";
                  pass = null;
                };
                redis = lib.optionalAttrs cfg.redis.createLocally {
                  host = "localhost";
                };
              } // (lib.optionalAttrs cfg.meilisearch.createLocally {
                meilisearch = {
                  host = "localhost";
                  port = config.services.meilisearch.listenPort;
                  ssl = false;
                };
              }))
          )
        ;
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/misskey migrateandstart";
        StateDirectory = "misskey";
        StateDirectoryMode = "700";
        TimeoutSec = 60;
        DynamicUser = true;
        User = "misskey";
        LockPersonality = true;
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectProc = "invisible";
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX AF_NETLINK";
      };
    };

    services.postgresql = lib.mkIf cfg.database.createLocally {
      enable = true;
      ensureDatabases = [ "misskey" ];
      ensureUsers = [
        {
          name = "misskey";
          ensureDBOwnership = true;
        }
      ];
    };

    services.redis.servers = lib.mkIf cfg.redis.createLocally {
      misskey = {
        enable = true;
        port = cfg.settings.redis.port;
      };
    };

    services.meilisearch = lib.mkIf cfg.meilisearch.createLocally {
      enable = true;
    };

    services.caddy.virtualHosts = lib.mkIf (cfg.reverseProxy.enable && cfg.reverseProxy.webserver ? caddy) {
      ${cfg.settings.url} = lib.mkMerge [
        cfg.reverseProxy.webserver.caddy
        {
          extraConfig = ''
            reverse_proxy localhost:${toString cfg.settings.port}
          '';
        }
      ];
    };

    services.nginx.virtualHosts = lib.mkIf (cfg.reverseProxy.enable && cfg.reverseProxy.webserver ? nginx) {
      ${cfg.settings.url} = lib.mkMerge [
        cfg.reverseProxy.webserver.nginx
        {
          locations."/" = {
            proxyPass = "http://localhost:${toString cfg.settings.port}";
            proxyWebsockets = true;
            recommendedProxySettings = true;
          };
        }
      ];
    };
  };
}

