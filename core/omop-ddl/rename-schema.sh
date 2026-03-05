# This script processes all .sql files in the current directory by replacing
# '@cdmDatabaseSchema' with 'public'. It places the modified DDL file (01_*)
# into processed/ddl/ and the rest (02_*, 03_*, 04_*) into processed/constraints/.

rm -rf processed
mkdir -p processed/ddl processed/constraints

for file in *.sql; do
  if [[ $file == 01_* ]]; then
    sed 's/@cdmDatabaseSchema/public/g' "$file" > "processed/ddl/$file"
  else
    sed 's/@cdmDatabaseSchema/public/g' "$file" > "processed/constraints/$file"
  fi
done
