#!/bin/sh
git add .
git commit -am "$1"
git push origin blog-source
cd _site/
rm -f CNAME
echo "blog.unarelith.net" > CNAME
git add .
git commit -am "$1"
git push origin master

