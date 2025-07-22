FROM ghcr.io/open-webui/open-webui:main

COPY sync_data.sh sync_data.sh

RUN chmod +x sync_data.sh && \
    sed -i "1r sync_data.sh" ./start.sh
