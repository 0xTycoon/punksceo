#!/usr/bin/php
<?php
// run report and push to github
$dir = __DIR__;
chdir($dir);
`npx hardhat run {$dir}/scripts/report.js`;
`git -C $dir commit -a -m "update stats"`;
`git -C $dir push origin report`;