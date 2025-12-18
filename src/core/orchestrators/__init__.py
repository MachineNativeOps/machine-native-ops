"""
Orchestrators Module - 協調器模組

提供統一的系統協調和管理功能。
"""

from .synergy_mesh_orchestrator import (
    SynergyMeshOrchestrator,
    ExecutionResult,
    SystemStatus,
    ExecutionStatus,
    ComponentType
)

# 使用 importlib 來處理 kebab-case 的文件名
import importlib.util
import sys
from pathlib import Path

# 導入 language-island-orchestrator
spec = importlib.util.spec_from_file_location(
    "language_island_orchestrator",
    Path(__file__).parent / "language-island-orchestrator.py"
)
if spec and spec.loader:
    language_island_orchestrator = importlib.util.module_from_spec(spec)
    sys.modules["language_island_orchestrator"] = language_island_orchestrator
    spec.loader.exec_module(language_island_orchestrator)
    LanguageIslandOrchestrator = language_island_orchestrator.LanguageIslandOrchestrator
else:
    # 備用方案：使用絕對導入
    try:
        from .language_island_orchestrator import LanguageIslandOrchestrator
    except ImportError:
        LanguageIslandOrchestrator = None


__all__ = [
    "SynergyMeshOrchestrator",
    "LanguageIslandOrchestrator",
    "ExecutionResult",
    "SystemStatus",
    "ExecutionStatus",
    "ComponentType"
]
