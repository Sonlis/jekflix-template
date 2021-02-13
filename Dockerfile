FROM nginx:latest
COPY _site /usr/share/nginx/html
COPY default.conf /etc/nginx/conf.d/default.conf
RUN chown nginx:nginx /usr/share/nginx/html/*
EXPOSE 80
ENTRYPOINT ["nginx", "-g", "daemon off;"]