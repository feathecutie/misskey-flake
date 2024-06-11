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
      database = {
        createLocally = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Create the PostgreSQL database locally";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.misskey = { };

    services.postresql = lib.mkIf cfg.createLocally {
      enable = true;
      ensureDatabases = [ ];
    };
  };
}
