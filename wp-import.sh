#!/bin/bash

WP_LANG=$1
WP_DATE=$2

cd $HOME/data/wikipedia

echo "Creating SQL file ..."
time mwimport.pl -l ${WP_LANG} ${WP_LANG}wiki-${WP_DATE}-pages-articles.xml  > ${WP_LANG}wiki-${WP_DATE}-pages-articles.sql

echo "Dropping database ..."
echo "DROP DATABASE ${WP_LANG}wiki;" | mysql -f -u root -pPASSWORD
echo "Creating database ..."
echo "CREATE DATABASE ${WP_LANG}wiki;" | mysql -f -u root -pPASSWORD
echo "GRANT INSERT, SELECT, UPDATE, DELETE, DROP, CREATE, ALTER, INDEX ON ${WP_LANG}wiki.* TO 'wikiuser'@'%' IDENTIFIED BY 'wikiuser_pw';" | mysql -f -u root -pPASSWORD
# schema from http://svn.wikimedia.org/viewvc/mediawiki/trunk/phase3/maintenance/tables.sql?view=markup
cat schema.sql | mysql -f -u wikiuser -pwikiuser_pw --default-character-set=utf8 ${WP_LANG}wiki

time mysql -f -u wikiuser -pwikiuser_pw --default-character-set=utf8 ${WP_LANG}wiki < ${WP_LANG}wiki-${WP_DATE}-pages-articles.sql
time mysql -f -u root -pPASSWORD --default-character-set=utf8 ${WP_LANG}wiki < ${WP_LANG}wiki-${WP_DATE}-categorylinks.sql
time mysql -f -u root -pPASSWORD --default-character-set=utf8 ${WP_LANG}wiki < ${WP_LANG}wiki-${WP_DATE}-category.sql

