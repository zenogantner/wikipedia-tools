#!/bin/bash

WP_LANG=$1
WP_DATE=$2

cd $HOME/data/wikipedia

wget http://download.wikimedia.org/${WP_LANG}wiki/${WP_DATE}/${WP_LANG}wiki-${WP_DATE}-pages-articles.xml.bz2
wget http://download.wikimedia.org/${WP_LANG}wiki/${WP_DATE}/${WP_LANG}wiki-${WP_DATE}-categorylinks.sql.gz
wget http://download.wikimedia.org/${WP_LANG}wiki/${WP_DATE}/${WP_LANG}wiki-${WP_DATE}-category.sql.gz

bunzip2 ${WP_LANG}wiki-${WP_DATE}-pages-articles.xml.bz2
gunzip ${WP_LANG}wiki-${WP_DATE}-category.sql.gz
gunzip ${WP_LANG}wiki-${WP_DATE}-categorylinks.sql.gz
