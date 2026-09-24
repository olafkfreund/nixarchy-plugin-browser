{
  description = "nixarchy-plugin-browser -- browse, audit and NixOS-check Omarchy plugins, in the shell on Super+Alt+U";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = nixpkgs.lib.genAttrs systems;

      manifest = builtins.fromJSON (builtins.readFile ./manifest.json);

      # Exactly what the plugin needs at runtime. Tests, the install scripts and
      # the intent/spec/plan documents are for whoever reads the repository, not
      # for the plugin folder. A new runtime file must be added here.
      files = [
        ./manifest.json
        ./qmldir
        ./LICENSE
        ./README.md
        ./CHANGELOG.md
        ./Model.js
        ./BarWidget.qml
        ./Menu.qml
        ./BrowserView.qml
        ./BrowserState.qml
        ./ShortcutSheet.qml
      ];
      dirs = [
        ./bin
        ./lib
        ./hypr
      ];

      tools = [
        "omarchy-plugin-audit"
        "omarchy-plugin-browser"
        "nixarchy-plugin-fix"
      ];

      pluginFor =
        pkgs:
        # runCommand and plain copies, deliberately: omarchy-plugin-validate
        # refuses any symlink inside a plugin folder, so symlinkJoin or a
        # linkFarm would fail validation at rebuild time.
        pkgs.runCommand "nixarchy-plugin-browser-${manifest.version}"
          {
            meta = with pkgs.lib; {
              description = "Omarchy plugin: browse the marketplace, audit plugins in a sandbox, check them for NixOS";
              homepage = "https://github.com/olafkfreund/nixarchy-plugin-browser";
              license = licenses.mit;
              platforms = platforms.linux;
            };
          }
          ''
            mkdir -p "$out"
            ${nixpkgs.lib.concatMapStringsSep "\n" (f: ''cp ${f} "$out/${baseNameOf f}"'') files}
            ${nixpkgs.lib.concatMapStringsSep "\n" (d: ''cp -r ${d} "$out/${baseNameOf d}"'') dirs}
          '';

      # The three tools on PATH for terminal use. Each runs the script inside
      # the plugin package, so it still finds its own lib/ next to it; the
      # scripts pin their own root-owned PATH, so nothing is added here.
      cliFor =
        pkgs: plugin:
        pkgs.runCommand "nixarchy-plugin-browser-cli-${manifest.version}"
          { meta.mainProgram = "omarchy-plugin-browser"; }
          ''
            mkdir -p "$out/bin"
            ${nixpkgs.lib.concatMapStringsSep "\n" (t: ''
              printf '#!%s\nexec %s %s "$@"\n' ${pkgs.runtimeShell} ${pkgs.bash}/bin/bash ${plugin}/bin/${t} > "$out/bin/${t}"
              chmod +x "$out/bin/${t}"
            '') tools}
          '';
    in
    {
      # The key bind, the one piece that lives outside the plugin folder. Writes
      # ~/.config/hypr/plugin-browser-binds.lua from the file the plugin ships,
      # so the Nix and non-Nix installs bind the same thing. bindings.lua still
      # has to load it: pcall(require, "hypr.plugin-browser-binds").
      homeManagerModules.default =
        { config, lib, ... }:
        let
          cfg = config.programs.nixarchy-plugin-browser;
        in
        {
          options.programs.nixarchy-plugin-browser.keybinding = lib.mkOption {
            # A chord only: the value lands inside a Lua string.
            type = lib.types.nullOr (lib.types.strMatching "[A-Z0-9_ +]+");
            default = "SUPER + ALT + U";
            description = "Chord that opens the Plugin Browser, in Omarchy's o.bind syntax. Null writes no bind.";
          };

          config = lib.mkIf (cfg.keybinding != null) {
            home.file.".config/hypr/plugin-browser-binds.lua".text =
              builtins.replaceStrings [ "SUPER + ALT + U" ] [ cfg.keybinding ]
                (builtins.readFile ./hypr/plugin-browser-binds.lua);
          };
        };
      homeModules = self.homeManagerModules;

      packages = forAll (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          default = plugin;
          plugin = pluginFor pkgs;
          cli = cliFor pkgs plugin;
        }
      );

      checks = forAll (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          plugin = self.packages.${system}.default;
        in
        {
          default =
            pkgs.runCommand "nixarchy-plugin-browser-check"
              {
                nativeBuildInputs = with pkgs; [
                  nodejs
                  jq
                  file
                  gnugrep
                  gnused
                  findutils
                  coreutils
                ];
              }
              ''
                # The package: no symlinks (the validator refuses them) and none of
                # the repository-only files.
                test "$(find ${plugin} -type l | wc -l)" = 0
                for x in tests intent spec plan install.sh uninstall.sh; do
                  test ! -e ${plugin}/$x || { echo "unexpected in the plugin: $x"; exit 1; }
                done

                # nixarchy's own build check for programs.nixarchy.plugins, verbatim:
                # no pacman or yay on a non-comment line of the plugin's code.
                hits=$(find ${plugin} -type f \( -name '*.qml' -o -name '*.js' -o -name '*.sh' -o -name '*.bash' \) -print0 |
                  xargs -0 -r grep -nHE '\bpacman\b|\byay\b' | grep -vE ':[0-9]+:[[:space:]]*(//|#)' || true)
                test -z "$hits" || { echo "$hits"; exit 1; }

                # The hermetic tier, against the packaged files. Host-tier tests
                # need the host's /run/current-system/sw (the scripts pin their
                # PATH to it), so they run outside the sandbox: tests/run.sh host.
                cp -r ${plugin} work && chmod -R u+w work && cp -r ${./tests} work/tests
                bash work/tests/run.sh hermetic
                touch $out
              '';

          # Every runtime file in the repository made it into the package: a
          # new QML or JS file not added to `files` fails here, not on a user.
          files =
            pkgs.runCommand "nixarchy-plugin-browser-files" { nativeBuildInputs = [ pkgs.diffutils ]; }
              ''
                rc=0
                for f in ${self}/*.qml ${self}/*.js ${self}/qmldir ${self}/manifest.json; do
                  n=$(basename "$f")
                  test -e ${plugin}/"$n" || { echo "missing from the plugin: $n"; rc=1; }
                done
                for d in bin lib hypr; do
                  diff -r ${self}/$d ${plugin}/$d || rc=1
                done
                test $rc = 0 && touch $out
              '';

          # The Home Manager module, evaluated against a stub of home.file (no
          # home-manager input): default chord, a custom chord, null, and a
          # value that would break out of the Lua string is refused.
          hm-module =
            let
              lib = nixpkgs.lib;
              stub = {
                options.home.file = lib.mkOption {
                  type = lib.types.attrsOf (
                    lib.types.submodule {
                      options.text = lib.mkOption { type = lib.types.str; };
                    }
                  );
                  default = { };
                };
              };
              homeFiles =
                keybinding:
                (lib.evalModules {
                  modules = [
                    stub
                    self.homeManagerModules.default
                  ]
                  ++ lib.optional (keybinding != "default") {
                    programs.nixarchy-plugin-browser.keybinding = keybinding;
                  };
                }).config.home.file;
              bind = keybinding: (homeFiles keybinding).".config/hypr/plugin-browser-binds.lua".text;
              results = {
                default = lib.hasInfix ''o.bind("SUPER + ALT + U"'' (bind "default");
                custom = lib.hasInfix ''o.bind("SUPER + SHIFT + P"'' (bind "SUPER + SHIFT + P");
                null = homeFiles null == { };
                injection =
                  (builtins.tryEval (builtins.deepSeq (bind "U\"); os.execute(\"") true)) == {
                    success = false;
                    value = false;
                  };
              };
            in
            assert lib.assertMsg (lib.all lib.id (
              lib.attrValues results
            )) "hm-module: ${builtins.toJSON results}";
            pkgs.writeText "nixarchy-plugin-browser-hm-module" (builtins.toJSON results);

          # Text sizes are bare Style.font.* tokens; no multiplier comes back (#26).
          no-text-multiplier =
            pkgs.runCommand "nixarchy-plugin-browser-no-text-multiplier"
              {
                nativeBuildInputs = with pkgs; [
                  gnugrep
                  findutils
                  gnused
                ];
              }
              ''
                bash ${./tests/no-text-multiplier.sh} ${self}
                touch $out
              '';
        }
      );
    };
}
