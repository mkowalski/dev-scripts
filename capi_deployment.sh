#!/usr/bin/env bash
set -o pipefail

source logging.sh
source utils.sh
source common.sh


HYPERSHIFT_REPO_URL="https://github.com/openshift/hypershift.git"
HYPERSHIFT_REPO_BRANCH="main"

IMAGE_REGISTRY_INTERNAL="image-registry.openshift-image-registry.svc:5000"
HYPERSHIFT_DEV_IMAGE="hypershift/hypershift-blabla:dev"

ASSETS_DIR="${OCP_DIR}/saved-assets/capi"


# OCP cluster must be configured to expose its internal image registry externally and allow any
# authenticated user to pull images from it. This will enable HyperShift component pods to pull
# the custom images we build.
function enable_internal_cluster_registry() {
    oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
    # OCP_DIR="~/dev-scripts/ocp/ostest/"
    oc login -u kubeadmin -p $(cat "${OCP_DIR}/auth/kubeadmin-password")
    oc registry login --to=$HOME/.docker/config.json --skip-check --registry $(oc get routes --namespace openshift-image-registry default-route -o jsonpath='{.spec.host}')
    oc create clusterrolebinding authenticated-registry-viewer --clusterrole registry-viewer --group system:authenticated
}

# We build HyperShift from the source and publish image in the OCP internal registry. That way
# HyperShift can be run directly from binaries and as a pod inside the cluster.
function build_hypershift() {
    pushd ${ASSETS_DIR}
    git clone --single-branch --branch ${HYPERSHIFT_REPO_BRANCH} ${HYPERSHIFT_REPO_URL}
    cd hypershift/

    REGISTRY="$(oc get routes --namespace openshift-image-registry default-route -o jsonpath='{.spec.host}')"
    IMAGE="${REGISTRY}/${HYPERSHIFT_DEV_IMAGE}"

    make build
    make RUNTIME=podman IMG=$IMAGE docker-build
    podman push --tls-verify=false $IMAGE

    popd
}

function install_hypershift() {
    pushd ${ASSETS_DIR}/hypershift/bin
    ./hypershift install --hypershift-image "${IMAGE_REGISTRY_INTERNAL}/${HYPERSHIFT_DEV_IMAGE}"

    popd
}

function uninstall_hypershift() {
    oc scale --replicas 0 --namespace hypershift deployments/operator
}

function install_capi() {
    mkdir -p "${ASSETS_DIR}"
    enable_internal_cluster_registry
    build_hypershift
    install_hypershift
}

function delete_all() {
    uninstall_hypershift
    rm -rf "${ASSETS_DIR}/hypershift"
}

"$@"
