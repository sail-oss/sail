# Makefile: convenience targets for managing sample agents

.PHONY: agents-add agents-delete agents-delete-all agents-recreate agents-list

agents-add:
	kubectl apply -R -f sample/agents

agents-delete:
	kubectl delete -R -f sample/agents --ignore-not-found

agents-delete-all:
	kubectl delete genericagents --all --ignore-not-found

agents-recreate: agents-delete agents-add

agents-list:
	kubectl get genericagents -o wide || kubectl get -R -f sample/agents
