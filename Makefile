.PHONY: run kill ps log

FUSION_PATTERN := [F]usion360|[A]dskIdentity|[A]DPClientService|[m]sedgewebview2|[a]dexmtsv|[p]roton run $(HOME)/.fusion360-proton2|[s]team.exe .*[F]usion360

NEUTRON_LOG_DIR := $(HOME)/.fusion360-proton2/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/Neutron Platform/logs
FUSION_USER_LOG_DIR := $(HOME)/.fusion360-proton2/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/Autodesk Fusion 360/C3WBQHDVEZAR/logs

run:
	bash -x ./launch-fusion.sh

kill:
	@pkill -f '$(FUSION_PATTERN)' || true

ps:
	@pgrep -af '$(FUSION_PATTERN)' || true

log:
	echo tail -f "$$(ls -t "$(NEUTRON_LOG_DIR)"/*.log "$(FUSION_USER_LOG_DIR)"/*.log | head -n 1)"
