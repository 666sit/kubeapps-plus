#!/bin/bash
BASE_DIR=$(
    cd "$(dirname "$0")"
    pwd
)
PROJECT_DIR=${BASE_DIR}
SCRIPT_DIR=${BASE_DIR}/scripts
UTILS_DIR=${BASE_DIR}/utils
action=$1

#工具函数
function read_from_input() {
    var=$1
    msg=$2
    choices=$3
    default=$4
    if [[ ! -z "${choices}" ]]; then
        msg="${msg} (${choices}) "
    fi
    if [[ -z "${default}" ]]; then
        msg="${msg} (无默认值)"
    else
        msg="${msg} (默认为${default})"
    fi
    echo -n "${msg}: "
    read input
    if [[ -z "${input}" && ! -z "${default}" ]]; then
        export ${var}="${default}"
    else
        export ${var}="${input}"
    fi
}
function set_docker_config() {
    cwd=$(pwd)
    cd ${PROJECT_DIR}
    url=$1
    project=$2
    user=$3
    password=$4
    authed=$(echo -n ${user}:${password} | base64)
    #bug
    # sed -i '/registry/c\ \"\'${url}'\",' utils/docker-config.json
    # sed -i "s,'password'/${auth},g" utils/docker-config.json

    echo '{
	    "auths": {
            "'${url}'": {
			    "auth": "'${authed}'"
		        }
	        },
	    "HttpHeaders": {
		    "User-Agent": "Docker-Client/18.09.9 (linux)"
	    }
    }' >utils/docker-config.json

    secret=$(base64 -w 0 utils/docker-config.json)
    all_variables_secret="secret=${secret}"
    #替换Secert
    resourcefile=`cat secrets/jenkins-secret.yaml`
    printf "$all_variables_secret\ncat << EOF\n$resourcefile\nEOF" | bash >apps/jenkins/templates/userdefined-secret.yaml
    resourcefile=`cat secrets/gitlab-secret.yaml`
    printf "$all_variables_secret\ncat << EOF\n$resourcefile\nEOF" | bash >apps/gitlab-ce/templates/userdefined-secret.yaml
    resourcefile=`cat secrets/sonar-secret.yaml`
    printf "$all_variables_secret\ncat << EOF\n$resourcefile\nEOF" | bash >apps/sonarqube/templates/userdefined-secret.yaml
    resourcefile=`cat secrets/harbor-secret.yaml`
    printf "$all_variables_secret\ncat << EOF\n$resourcefile\nEOF" | bash >apps/harbor/templates/userdefined-secret.yaml
    resourcefile=`cat secrets/weave-scope-secret.yaml`
    printf "$all_variables_secret\ncat << EOF\n$resourcefile\nEOF" | bash >apps/weave-scope/templates/userdefined-secret.yaml
     
    #TODO
    #替换source
    # registryfile=`cat apps/jenkins/values.yaml`
    # all_variables_source="imageregistry=\"${url}\""
    # printf "$all_variables_source\ncat << EOF\n$registryfile\nEOF" | bash >apps/jenkins/values.yaml
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/jenkins/values_default.yaml > apps/jenkins/values.yaml
    #Gitlab
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/gitlab-ce/values_default.yaml > apps/gitlab-ce/values.yaml
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/gitlab-ce/charts/postgresql/values_default.yaml > apps/gitlab-ce/charts/postgresql/values.yaml
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/gitlab-ce/charts/redis/values_default.yaml > apps/gitlab-ce/charts/redis/values.yaml

    #
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/sonarqube/values_default.yaml > apps/sonarqube/values.yaml
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/sonarqube/charts/mysql/values_default.yaml > apps/sonarqube/charts/mysql/values.yaml
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/sonarqube/charts/postgresql/values_default.yaml > apps/sonarqube/charts/postgresql/values.yaml
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/harbor/values_default.yaml > apps/harbor/values.yaml
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/harbor/charts/postgresql/values_default.yaml > apps/harbor/charts/postgresql/values.yaml
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/harbor/charts/redis/values_default.yaml > apps/harbor/charts/redis/values.yaml
    sed "s/imageregistryvalue/\"${url}\/${project}\"/g" apps/weave-scope/values_default.yaml > apps/weave-scope/values.yaml

}

## 检查环境 安装helm push
function env_check() {
    echo "检查Docker......"
    docker -v
    if [ $? -eq 0 ]; then
        echo "检查到Docker已安装!"
    else
        echo "请先安装Docker"
    fi
    echo "检查Helm......"
    helm version
    if [ $? -eq 0 ]; then
        echo "检查到Helm已安装!"
    else
        echo "请先安装Helm"
    fi
    #安装Helm Push Plugins
    \cp -rf ${UTILS_DIR}/push/ $(helm home)/plugins/
    echo "安装 Push Plugins 完成"
}
registry_host=""
registry_project=""
registry_user=""
registry_pass=""
function set_external_registry() {

    read_from_input registry_host "请输入registry的域名" "" "${registry_host}"

    read_from_input registry_project "请输入registry的项目名" "" "${registry_project}"

    read_from_input registry_user "请输入registry的用户名" "" "${registry_user}"

    read_from_input registry_pass "请输入registry的密码" "" "${registry_pass}"

    #test_registry_connect ${registry_host} ${registry_port} ${registry_user} ${registry_pass} ${registry_db}
    # if [[ "$?" != "0" ]]; then
    #     echo "测试连接数据库失败, 请重新设置"
    #     set_external_registry
    #     return
    # fi
    set_docker_config ${registry_host} ${registry_project} ${registry_user} ${registry_pass}
}

function set_internal_registry() {
    registry_host="registry.kubeapps.fit2cloud.com"
    registry_project="kubeapps-plus"
    registry_user="admin"
    registry_pass="admin123"
    set_docker_config ${registry_host} ${registry_project} ${registry_user} ${registry_pass}
}

function set_registry() {
    echo ">>> 配置registry"
    use_external_registry="n"
    read_from_input use_external_registry "是否使用外部Docker Image Registry" "y/n" "${use_external_registry}"

    if [[ "${use_external_registry}" == "y" ]]; then
        set_external_registry
    else
        set_internal_registry
    fi
}

#docker retag & push

function docker_upload_image() {

    #jenkins start
    cd ${PROJECT_DIR}/apps/image
    docker load <jenkins.jar
    docker load <jenkins-exporter.jar
    docker tag 30a01ef4eaab ${registry_host}/${registry_project}/docker.io/bitnami/jenkins:2.204.1-debian-9-r0
    docker tag ffca41295e0d ${registry_host}/${registry_project}/docker.io/bitnami/jenkins-exporter:0.20171225.0-debian-9-r127
    docker push ${registry_host}/${registry_project}/docker.io/bitnami/jenkins:2.204.1-debian-9-r0
    docker push ${registry_host}/${registry_project}/docker.io/bitnami/jenkins-exporter:0.20171225.0-debian-9-r127
    #jenkins end

    #gitlab start
    docker load < gitlab.jar
    docker tag 6099ff61e4ff ${registry_host}/${registry_project}/gitlab/gitlab:lts
    docker push ${registry_host}/${registry_project}/gitlab/gitlab:lts
    docker load < postgres.jar
    docker tag be622cf06787 ${registry_host}/${registry_project}/postgres:9.6
    docker push ${registry_host}/${registry_project}/postgres:9.6
    docker load < redis.jar
    docker tag 40856dba0c5d ${registry_host}/${registry_project}/bitnami/redis:3.2.9-r2
    docker push ${registry_host}/${registry_project}/bitnami/redis:3.2.9-r2
    #gitlab end

    #sonarqube start
    docker load <sonarqube.jar
    docker tag ea9ce8f562b5 ${registry_host}/${registry_project}/sonarqube/sonarqube:lts
    docker push ${registry_host}/${registry_project}/sonarqube/sonarqube:lts
    docker load < mysql-5.7.jar
    docker tag 4b3b6b994512 ${registry_host}/${registry_project}/mysql:5.7.14
    docker push ${registry_host}/${registry_project}/mysql:5.7.14
    docker load < busybox-125.jar
    docker tag 2b8fd9751c4c ${registry_host}/${registry_project}/busybox:1.25.0
    docker push ${registry_host}/${registry_project}/busybox:1.25.0
    docker load < busybox-131.jar
    docker tag 6d5fcfe5ff17 ${registry_host}/${registry_project}/busybox:1.31.0
    docker push ${registry_host}/${registry_project}/busybox:1.31.0
    docker load < postgres-9-6-2.jar
    docker tag b3b8a2229953 ${registry_host}/${registry_project}/postgres:9.6.2
    docker push ${registry_host}/${registry_project}/postgres:9.6.2
    #sonarqube end

    #harbor start
    docker load < harbor-notary-server.jar
    docker load < harbor-portal.jar
    docker load < harbor-jobservice.jar
    docker load < harbor-chartmuseum.jar
    docker load < harbor-registry.jar
    docker load < harbor-registryctl.jar
    docker load < harbor-clair.jar
    docker load < harbor-jobservice.jar
    docker load < harbor-notary-signer.jar
    docker load < harbor-nginx.jar
    docker load < harbor-minideb.jar
    docker load < harbor-core.jar
    docker load < gitlab-postgresql.jar
    docker load < postgres-exporter.jar
    docker load < harbor-radis.jar
    docker load < redis-sentinel.jar
    docker load < redis-exporter.jar

    docker tag d463d8c692e8 ${registry_host}/${registry_project}/bitnami/harbor-portal:1.10.0-debian-9-r0
    docker tag adef6d703e66 ${registry_host}/${registry_project}/bitnami/harbor-core:1.10.0-debian-9-r3
    docker tag 057377fcb879 ${registry_host}/${registry_project}/bitnami/harbor-jobservice:1.10.0-debian-9-r3
    docker tag 9d612e5956c4 ${registry_host}/${registry_project}/bitnami/chartmuseum:0.11.0-debian-9-r1
    docker tag 8afee10225bd ${registry_host}/${registry_project}/bitnami/harbor-registry:1.10.0-debian-9-r3
    docker tag 810432b24ea0 ${registry_host}/${registry_project}/bitnami/harbor-registryctl:1.10.0-debian-9-r3
    docker tag 4970db9b1e5f ${registry_host}/${registry_project}/bitnami/harbor-clair:1.10.0-debian-9-r3
    docker tag dac437e264bd ${registry_host}/${registry_project}/bitnami/harbor-notary-server:1.10.0-debian-9-r3
    docker tag ef51b2e2f1cf ${registry_host}/${registry_project}/bitnami/harbor-notary-signer:1.10.0-debian-9-r3
    docker tag 14f7a3ce8fb7 ${registry_host}/${registry_project}/bitnami/nginx:1.16.1-debian-9-r116
    docker tag ff2799e30418 ${registry_host}/${registry_project}/bitnami/minideb:stretch
    docker tag d770c426a6fa ${registry_host}/${registry_project}/bitnami/postgresql:11.6.0-debian-9-r0
    docker tag f76c863e298b ${registry_host}/${registry_project}/bitnami/postgres-exporter:0.7.0-debian-9-r12
    docker tag 75ff9b143e44 ${registry_host}/${registry_project}/bitnami/redis:5.0.7-debian-9-r0
    docker tag 4f8dcc20b014 ${registry_host}/${registry_project}/bitnami/redis-sentinel:5.0.6-debian-9-r6
    docker tag 2f6296b551e9 ${registry_host}/${registry_project}/bitnami/redis-exporter:1.3.4-debian-9-r4


    docker push ${registry_host}/${registry_project}/bitnami/harbor-portal:1.10.0-debian-9-r0
    docker push ${registry_host}/${registry_project}/bitnami/harbor-core:1.10.0-debian-9-r3
    docker push ${registry_host}/${registry_project}/bitnami/harbor-jobservice:1.10.0-debian-9-r3
    docker push ${registry_host}/${registry_project}/bitnami/chartmuseum:0.11.0-debian-9-r1
    docker push ${registry_host}/${registry_project}/bitnami/harbor-registry:1.10.0-debian-9-r3
    docker push ${registry_host}/${registry_project}/bitnami/harbor-registryctl:1.10.0-debian-9-r3
    docker push ${registry_host}/${registry_project}/bitnami/harbor-clair:1.10.0-debian-9-r3
    docker push ${registry_host}/${registry_project}/bitnami/harbor-notary-server:1.10.0-debian-9-r3
    docker push ${registry_host}/${registry_project}/bitnami/harbor-notary-signer:1.10.0-debian-9-r3
    docker push ${registry_host}/${registry_project}/bitnami/nginx:1.16.1-debian-9-r116
    docker push ${registry_host}/${registry_project}/bitnami/minideb:stretch
    docker push ${registry_host}/${registry_project}/bitnami/postgresql:11.6.0-debian-9-r0
    docker push ${registry_host}/${registry_project}/bitnami/postgres-exporter:0.7.0-debian-9-r12
    docker push ${registry_host}/${registry_project}/bitnami/redis:5.0.7-debian-9-r0
    docker push ${registry_host}/${registry_project}/bitnami/redis-sentinel:5.0.6-debian-9-r6
    docker push ${registry_host}/${registry_project}/bitnami/redis-exporter:1.3.4-debian-9-r4
    #harbor end

    #weave-scope start
    docker load < weave-scope.jar
    docker tag 4178113a354d ${registry_host}/${registry_project}/weaveworks/scope:1.12.0
    docker push ${registry_host}/${registry_project}/weaveworks/scope:1.12.0
    #weave-scope end
}

#打包Helm Chart

# function pakcage_chart() {
#     echo ">>> 打包Chart"
#     cd ${PROJECT_DIR}/jenkins
#     helm pakcage .
#     if [ $? -eq 0 ]; then
#         echo ">>> 打包完成"
#     else
#         echo ">>> 打包失败"
#     fi
# }

#配置chart 仓库

function set_external_chartrepo() {
    repo_url=""
    read_from_input repo_url "请输入Chart Repo访问地址 例: https://xx.xx.xx.xx/chartrepo/myproject，注意必须输入带协议的完整地址" "" "${repo_url}"

    repo_username=""
    read_from_input repo_username "请输入Repo的用户名" "" "${repo_username}"

    repo_password=""
    read_from_input repo_password "请输入Repo的密码" "" "${repo_password}"

    helm repo add localrepo ${repo_url} --username ${repo_username} --password ${repo_password}
}

function set_internal_chartrepo() {
    helm repo add localrepo http://chartmuseum.kubeapps.fit2cloud.com
}

function set_chartrepo() {
    echo ">>> 配置 Chart 仓库"
    use_external_chartrepo="n"
    read_from_input use_external_chartrepo "是否使用外部 Chart 仓库" "y/n" "${use_external_chartrepo}"

    if [[ "${use_external_chartrepo}" == "y" ]]; then
        set_external_chartrepo
    else
        set_internal_chartrepo
    fi
}

#上传Chart 到 Chart Repo

function upload_chart() {
    cd ${PROJECT_DIR}/apps/gitlab-ce
    helm package .
    helm push . localrepo -f
    cd ${PROJECT_DIR}/apps/harbor
    helm package .
    helm push . localrepo -f
    cd ${PROJECT_DIR}/apps/jenkins
    helm package .
    helm push . localrepo -f
    cd ${PROJECT_DIR}/apps/sonarqube
    helm package .
    helm push . localrepo -f
    cd ${PROJECT_DIR}/apps/weave-scope
    helm package .
    helm push . localrepo -f
    if [ $? -eq 0 ]; then
        echo ">>> 上传完成"
    else
        echo ">>> 上传失败"
    fi
}

function usage() {
    echo "Kubeapps 推送Docker镜像及Helm Chart包脚本"
    echo
    echo "Usage: "
    echo "  ./kubeappsctl.sh [COMMAND] [ARGS...]"
    echo "  ./kubeappsctl.sh --help"
    echo
    echo "Commands: "
    echo "  start 推送Docker镜像及Helm Chart包"
}

#主进程
function main() {
    case "${action}" in
    start)
        env_check
        set_registry
        docker_upload_image
        set_chartrepo
        upload_chart
        ;;
    help)
        usage
        ;;
    --help)
        usage
        ;;
    *)
        usage
        ;;
    esac
}
main
