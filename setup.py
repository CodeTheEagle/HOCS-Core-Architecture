from setuptools import setup, find_packages

with open("README.md", "r") as fh:
    long_description = fh.read()

setup(
    name="hocs-core",
    version="2.4.1",
    author="CodeTheEagle Team (Yusuf & Mikail)",
    author_email="contact@hocs-ai.com",
    description="Hardware Abstraction Layer for Hybrid Optical Computing System",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/CodeTheEagle/HOCS-Core-Architecture",
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Science/Research",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
        "License :: Proprietary",
        "Programming Language :: Python :: 3.10",
        "Operating System :: POSIX :: Linux",
    ],
    python_requires=">=3.8",
    install_requires=[
        "numpy",
        "pyserial",
        "smbus2",
    ],
    entry_points={
        "console_scripts": [
            "hocs-cli=host_api.cli:main",
        ],
    },
)
