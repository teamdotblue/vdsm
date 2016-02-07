#!/bin/bash -ex
export LIBGUESTFS_BACKEND=direct
PREFIX="$PWD"/automation/vdsm_functional
EXPORTS="$PWD"/exported-artifacts
TEST_PATH="functional"
FUNCTIONAL_TESTS_LIST=" \
    $TEST_PATH/supervdsmFuncTests.py"

DISABLE_TESTS_LIST=" \
    $TEST_PATH/sosPluginTests.py \
    $TEST_PATH/vmRecoveryTests.py \
    $TEST_PATH/momTests.py \
    $TEST_PATH/networkTests.py \
    $TEST_PATH/vmQoSTests.py \
    $TEST_PATH/virtTests.py \
    $TEST_PATH/storageTests.py \
    $TEST_PATH/networkTestsOVS.py"

# Creates RPMS
./automation/build-artifacts.sh

if [[ -d "$PREFIX" ]]; then
    pushd "$PREFIX"
    echo 'cleaning old lago env'
    lago cleanup || :
    popd
    rm -rf "$PREFIX"
fi


# Ugly hack to include local built rpms
sed -e "s|@PWD@|$PWD|g" automation/reposync-config.repo.tpl \
> automation/reposync-config.repo
rm -rf /var/lib/lago/reposync/local-vdsm-build-*
createrepo exported-artifacts

# Fix when running in a chroot in fc2*
[[ -e /usr/libexec/qemu-kvm ]] \
|| ln -s /usr/bin/qemu-kvm /usr/libexec/qemu-kvm

TEMPLATES_REPO=http://templates.ovirt.org/repo/repo.metadata
# If testing locally in the rh office you can use this one
#TEMPLATES_REPO=http://10.35.18.63/repo/repo.metadata

lago init \
    "$PREFIX" \
    automation/lago-env.json \
    --template-repo-path "$TEMPLATES_REPO"

cd "$PREFIX"

# Make sure that there are no cached local repos, will not be needed once lago
# can handle local rpms properly
rm -rf /var/lib/lago/repos/local-vdsm*
lago ovirt reposetup \
    --reposync-yum-config ../reposync-config.repo

VMS_PREFIX="vdsm_functional_tests_host-"
failed=0
for distro in fc23; do
    vm_name="${VMS_PREFIX}${distro}"
    # starting vms one by one to avoid exhausting memory in the host, it will
    lago start "$vm_name"
    # the ovirt deploy is needed because it will not start the local repo
    # otherwise
    lago ovirt deploy
    {
        lago shell "$vm_name" -c \
            " \
                cd /usr/share/vdsm/tests
                ./run_tests.sh \
                    --with-xunit \
                    --xunit-file=/tmp/nosetests-${distro}.xml \
                    -s \
                    $FUNCTIONAL_TESTS_LIST \
            " \
        || failed=$?
    } | tee "$EXPORTS/functional_tests_stdout.$distro.log"

    lago copy-from-vm \
        "$vm_name" \
        "/tmp/nosetests-${distro}.xml" \
        "$EXPORTS/nosetests-${distro}.xml" || :
    lago stop "$vm_name"
done

lago cleanup

cat "$EXPORTS/functional_tests_stdout.$distro.log"

[[ -e "logs" ]] \
&& {
    tar cvzf "$EXPORTS/lago-logs.tar.gz" logs
}

exit $failed
