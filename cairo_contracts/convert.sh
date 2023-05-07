for f in  ./**/*.cairo ./**/**/*.cairo ./**/**/**/*.cairo ; do

  cairo-migrate --one_item_per_line -i --migrate_syntax --single_return_functions $f
  
done;