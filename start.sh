# eval $(minikube docker-env)
# docker build -t quorum -f quorum.Dockerfile .
# docker tag quorum asia.gcr.io/consortiumchain/quorum
# docker build -t explorer-ui -f ui.Dockerfile .
# docker tag explorer-ui asia.gcr.io/consortiumchain/explorer-ui
# docker build -t explorer-backend -f backend.Dockerfile .
# docker tag explorer-backend asia.gcr.io/consortiumchain/explorer-backend
./setup.sh
# minikube start
# kubectl config use-context minikube
# kubectl create -f quorum_config.yaml,crux_config.yaml,backend_config.yaml,node_secret.yaml,ebs-standard-storage-class.yaml,consortium.yaml
# kubectl delete -f quorum_config.yaml,crux_config.yaml,backend_config.yaml,node_secret.yaml,ebs-standard-storage-class.yaml,consortium.yaml