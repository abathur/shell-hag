setup() {
    {
        TEST_TMP="$(mktemp -d)"
        cp tests/*.{bats,bash} "$TEST_TMP"/ > /dev/null
        pushd "$TEST_TMP"
    } > /dev/null
}
teardown() {
    {
        popd > /dev/null
    } > /dev/null
}
