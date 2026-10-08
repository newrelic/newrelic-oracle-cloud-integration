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
# Apply all available OS security updates, then drop pip. pip is unused at
# runtime (the entrypoint is fdk) and the pinned versions in its vendored
# dependency manifest are reported as vulnerabilities by image scanners.
#
# The rpm-owned pip is removed through microdnf so the rpm database stays
# consistent. The copy under /usr/local was installed by pip itself rather than
# by rpm, so it has to be deleted directly.
#
# Two things are deliberately left in place: setuptools/pkg_resources, because
# pbr and pytz fall back to them at runtime, and /usr/share/python3.11-wheels,
# because python3.11-libs requires the wheel packages that own it and removing
# them would drag the interpreter out with them.
RUN microdnf update -y && \
    microdnf remove -y python3.11-pip && \
    microdnf clean all && \
    rm -fr /usr/local/lib/python3.11/site-packages/pip \
           /usr/local/lib/python3.11/site-packages/pip-*.dist-info \
           /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.11 \
           /var/cache/dnf /var/cache/yum
COPY --from=build-stage /python /python
COPY --from=build-stage /function /function
RUN chmod -R o+r /function
ENV PYTHONPATH=/function:/python
# Set the function handler
ENTRYPOINT ["/python/bin/fdk", "/function/function.py", "handler"]
