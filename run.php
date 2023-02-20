#!/usr/bin/php
<?php

$dir = __DIR__;
chdir($dir);
`npx hardhat run {$dir}/scripts/report.js`;
`git -C $dir commit -a`;
`git -C $dir push origin report`;