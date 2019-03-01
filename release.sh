#!/bin/bash
echo "Creating a new release"
migration_version=$(cat package.json  | jq -r '.devDependencies."@daostack/migration"')
docker_compose_migration_version=$(cat docker-compose.yml | grep daostack/migration | cut -d ":" -f 3 | sed "s/'//")
package_version=$(cat package.json | jq -r '.version')
image_version=ganache-$migration_version-$package_version

echo $docker_compose_migration_version
echo $migration_version
if [[ $docker_compose_migration_version != $migration_version ]]; then
  echo "The migration version in the docker-compose file is not the same as the one in package.json ($docker_compose_migration_version != $migration_version)"
  exit
fi
echo "(Re)bulding docker containers..."
docker-compose down -v
docker-compose build
docker-compose up -d

# wait a bit for graph-node to come (it will redirect with a 302)
echo "wating for subgraph to start"
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' 127.0.0.1:8000)" != "200" ]]; do sleep 5; done

echo "moving .env to make sure we have default settings"
mv .env .env_backup
echo "deploying subgraph"
npm run deploy
echo "restoring .env file"
mv .env .env_backup


# commit the postgres image
container_id=$(docker ps  -f "name=postgres" -l -q)
image_name=daostack/subgraph-postgres
echo "docker commit $container_id $image_name:$image_version"
docker commit $container_id $image_name:$image_version
echo "docker push $image_name:$image_version"
docker push $image_name:$image_version

# commit the ipfs  image
container_id=$(docker ps  -f "name=ipfs" -l -q)
image_name=daostack/subgraph-ipfs
echo "docker commit $container_id $image_name:$image_version"
docker commit $container_id $image_name:$image_version
echo "docker push $image_name:$image_version"
docker push $image_name:$image_version



docker-compose down -v
# tag on github
git tag -a $image_version -m "Release of version $image_name:$image_version"
git push --tags
# done
echo "Done!"
