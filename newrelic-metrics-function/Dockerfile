FROM fnproject/python:3.11-dev AS build-stage
WORKDIR /function
ADD requirements.txt /function/
ARG FUNCTION_BUILD_VERSION
ENV FUNCTION_BUILD_VERSION=${FUNCTION_BUILD_VERSION}
RUN pip3 install --target /python/  --no-cache --no-cache-dir -r requirements.txt && \
    rm -fr ~/.cache/pip /tmp* requirements.txt func.yaml Dockerfile .venv && \
    chmod -R o+r /python && \
    groupadd --gid 1000 fn && \
    adduser --uid 1000 --gid fn fn
ADD . /function/
RUN rm -fr /function/.pip_cache
FROM fnproject/python:3.11
WORKDIR /function
COPY --from=build-stage /python /python
COPY --from=build-stage /function /function
RUN chmod -R o+r /function
ENV PYTHONPATH=/function:/python
# Set the function handler
ENTRYPOINT ["/python/bin/fdk", "/function/function.py", "handler"]
