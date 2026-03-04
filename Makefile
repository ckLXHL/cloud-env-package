# Cloud Dev Environment - 顶层统一入口
# 用法: make <target> [变量=值 ...]
#
# 示例:
#   make build-all                        # 全量构建
#   make build LAYER=toolchain            # 构建工具链层
#   make build IMAGE=cpp                  # 构建指定镜像
#   make push REGISTRY=aliyun-acr        # 推送到指定仓库
#   make sync TARGET=oss                  # 同步到阿里云OSS
#   make bootstrap SCENE=full            # 目标机一键初始化

.PHONY: help build build-all build-dry push push-all push-manifest push-all-registries \
        sync sync-oss sync-obs load bootstrap rollback \
        ansible-bootstrap ansible-deploy ansible-update ansible-health \
        clean clean-cache

# ============================================================
# 默认变量（可通过命令行覆盖）
# ============================================================
REGISTRY       ?= ghcr.io/ckLXHL
LAYER          ?= all
IMAGE          ?=
ARCH           ?=
VERSION        ?= latest
TARGET         ?= oss
SCENE          ?= full
RUNTIME        ?=
PUSH           ?= false
CACHE          ?= true
DRY_RUN        ?= false
ALL_REGISTRIES ?= false
ANSIBLE_INVENTORY ?= ansible/inventory/hosts.ini

# 脚本路径
SCRIPTS_DIR := scripts
BUILD_SCRIPT  := $(SCRIPTS_DIR)/build.sh
PUSH_SCRIPT   := $(SCRIPTS_DIR)/push.sh
SYNC_SCRIPT   := $(SCRIPTS_DIR)/sync.sh
LOAD_SCRIPT   := $(SCRIPTS_DIR)/load.sh
BOOTSTRAP_SCRIPT := $(SCRIPTS_DIR)/bootstrap.sh

# ============================================================
# 帮助
# ============================================================
help: ## 显示帮助信息
	@echo ""
	@echo "Cloud Dev Environment - 统一管理入口"
	@echo "======================================"
	@echo ""
	@echo "构建命令:"
	@echo "  make build-all                 全量构建所有镜像"
	@echo "  make build LAYER=base          构建指定层 (base/toolchain/services/compose)"
	@echo "  make build IMAGE=cpp           构建指定镜像"
	@echo "  make build IMAGE=cpp ARCH=arm64 指定架构构建"
	@echo "  make build-dry IMAGE=cpp       预览模式（不实际构建）"
	@echo ""
	@echo "推送命令:"
	@echo "  make push REGISTRY=aliyun-acr  推送到指定仓库"
	@echo "  make push LAYER=toolchain      推送指定层"
	@echo "  make push-all REGISTRY=ghcr    全量推送到单仓库"
	@echo "  make push-all-registries       全量推送到所有仓库"
	@echo "  make push-manifest IMAGE=cpp   创建多架构 manifest"
	@echo ""
	@echo "同步命令:"
	@echo "  make sync TARGET=oss           同步到阿里云OSS"
	@echo "  make sync TARGET=obs           同步到华为OBS"
	@echo "  make sync TARGET=all           同步到所有对象存储"
	@echo ""
	@echo "目标机命令:"
	@echo "  make load SCENE=full           下载并加载镜像"
	@echo "  make bootstrap SCENE=cpp       一键初始化目标机"
	@echo "  make rollback VERSION=v1.1.0   回滚到指定版本"
	@echo ""
	@echo "Ansible 命令:"
	@echo "  make ansible-bootstrap         初始化目标机集群"
	@echo "  make ansible-deploy            部署开发环境"
	@echo "  make ansible-update            检查并更新"
	@echo "  make ansible-health            健康检查"
	@echo ""
	@echo "维护命令:"
	@echo "  make clean                     清理临时文件"
	@echo "  make clean-cache               清理 BuildKit 缓存"
	@echo ""
	@echo "变量:"
	@echo "  REGISTRY=$(REGISTRY)"
	@echo "  VERSION=$(VERSION)"
	@echo "  ARCH=$(ARCH)"
	@echo "  SCENE=$(SCENE)"
	@echo ""

# ============================================================
# 构建目标
# ============================================================
build: ## 按条件构建镜像（使用 LAYER/IMAGE/ARCH 变量）
	@echo "构建镜像 (LAYER=$(LAYER), IMAGE=$(IMAGE), ARCH=$(ARCH))"
	@REGISTRY=$(REGISTRY) \
	 LAYER=$(LAYER) \
	 IMAGE=$(IMAGE) \
	 ARCH=$(ARCH) \
	 PUSH=$(PUSH) \
	 CACHE=$(CACHE) \
	 DRY_RUN=$(DRY_RUN) \
	 bash $(BUILD_SCRIPT)

build-all: ## 全量构建所有镜像
	@$(MAKE) build LAYER=all

build-dry: ## 预览模式构建（不实际执行）
	@$(MAKE) build DRY_RUN=true

build-base: ## 构建 L0 基础镜像
	@$(MAKE) build LAYER=base

build-toolchain: ## 构建 L1 工具链镜像
	@$(MAKE) build LAYER=toolchain

build-services: ## 构建 L2 服务镜像
	@$(MAKE) build LAYER=services

build-compose: ## 构建 L3 场景组合镜像
	@$(MAKE) build LAYER=compose

# ============================================================
# 推送目标
# ============================================================
push: ## 推送镜像到指定仓库（使用 REGISTRY/LAYER/IMAGE 变量）
	@echo "推送镜像 (REGISTRY=$(REGISTRY), LAYER=$(LAYER), IMAGE=$(IMAGE))"
	@REGISTRY=$(REGISTRY) \
	 LAYER=$(LAYER) \
	 IMAGE=$(IMAGE) \
	 VERSION=$(VERSION) \
	 bash $(PUSH_SCRIPT)

push-all: ## 全量推送到指定仓库
	@$(MAKE) push LAYER=all

push-all-registries: ## 全量推送到所有配置的仓库
	@REGISTRY=$(REGISTRY) \
	 LAYER=all \
	 ALL_REGISTRIES=true \
	 bash $(PUSH_SCRIPT) --all-registries

push-manifest: ## 创建并推送多架构 manifest（需要指定 IMAGE）
	@[ -n "$(IMAGE)" ] || (echo "错误: 请指定 IMAGE=<镜像名>" && exit 1)
	@echo "创建 manifest: $(REGISTRY)/$(IMAGE):$(VERSION)"
	docker manifest create \
		$(REGISTRY)/$(IMAGE):$(VERSION) \
		--amend $(REGISTRY)/$(IMAGE):$(VERSION)-amd64 \
		--amend $(REGISTRY)/$(IMAGE):$(VERSION)-arm64
	docker manifest push $(REGISTRY)/$(IMAGE):$(VERSION)

# ============================================================
# 同步目标
# ============================================================
sync: ## 同步镜像到对象存储（TARGET=oss/obs/all）
	@echo "同步到: $(TARGET)"
	@TARGET=$(TARGET) \
	 VERSION=$(VERSION) \
	 ARCH=$(ARCH) \
	 bash $(SYNC_SCRIPT) --target $(TARGET)

sync-oss: ## 同步到阿里云OSS
	@$(MAKE) sync TARGET=oss

sync-obs: ## 同步到华为OBS
	@$(MAKE) sync TARGET=obs

# ============================================================
# 目标机操作
# ============================================================
load: ## 下载并加载镜像到本地（SCENE/ARCH/VERSION 变量）
	@SCENE=$(SCENE) \
	 ARCH=$(ARCH) \
	 VERSION=$(VERSION) \
	 RUNTIME=$(RUNTIME) \
	 bash $(LOAD_SCRIPT) \
	   --scene $(SCENE) \
	   $(if $(ARCH),--arch $(ARCH),) \
	   --version $(VERSION)

bootstrap: ## 目标机一键初始化（SCENE/ARCH/REGISTRY_SOURCE 变量）
	@SCENE=$(SCENE) \
	 ARCH=$(ARCH) \
	 VERSION=$(VERSION) \
	 bash $(BOOTSTRAP_SCRIPT) \
	   --scene $(SCENE) \
	   $(if $(ARCH),--arch $(ARCH),) \
	   --version $(VERSION)

rollback: ## 回滚到指定版本（需要指定 VERSION）
	@[ "$(VERSION)" != "latest" ] || (echo "错误: 请指定 VERSION=v<x.y.z>" && exit 1)
	@echo "回滚到版本: $(VERSION)"
	@$(MAKE) load VERSION=$(VERSION) SCENE=$(SCENE)

# ============================================================
# Ansible 操作
# ============================================================
ansible-bootstrap: ## 使用 Ansible 初始化目标机集群
	ansible-playbook \
		-i $(ANSIBLE_INVENTORY) \
		ansible/playbooks/bootstrap.yml \
		$(ANSIBLE_ARGS)

ansible-deploy: ## 使用 Ansible 部署开发环境
	ansible-playbook \
		-i $(ANSIBLE_INVENTORY) \
		ansible/playbooks/deploy-env.yml \
		-e "devenv_scene=$(SCENE)" \
		-e "devenv_version=$(VERSION)" \
		$(ANSIBLE_ARGS)

ansible-update: ## 使用 Ansible 更新开发环境
	ansible-playbook \
		-i $(ANSIBLE_INVENTORY) \
		ansible/playbooks/update-env.yml \
		$(ANSIBLE_ARGS)

ansible-health: ## 使用 Ansible 健康检查
	ansible-playbook \
		-i $(ANSIBLE_INVENTORY) \
		ansible/playbooks/health-check.yml \
		$(ANSIBLE_ARGS)

# ============================================================
# 维护目标
# ============================================================
clean: ## 清理临时文件
	@echo "清理临时文件..."
	@rm -rf /tmp/devenv-* 2>/dev/null || true
	@echo "清理完成"

clean-cache: ## 清理 Docker BuildKit 缓存
	@echo "清理 BuildKit 缓存..."
	@docker buildx prune --force 2>/dev/null || true
	@docker builder prune --force 2>/dev/null || true
	@echo "缓存清理完成"

# 显示当前配置
show-config: ## 显示当前配置
	@echo "当前配置:"
	@echo "  REGISTRY    = $(REGISTRY)"
	@echo "  VERSION     = $(VERSION)"
	@echo "  SCENE       = $(SCENE)"
	@echo "  ARCH        = $(ARCH)"
	@echo "  LAYER       = $(LAYER)"
	@echo "  IMAGE       = $(IMAGE)"
	@echo "  TARGET      = $(TARGET)"
