use std::{ fs, io::Write, path::Path };

enum TemplateNode {
    File {
        name: &'static str,
        content: &'static str,
    },
    Dir {
        name: &'static str,
        children: &'static [TemplateNode],
    },
}

fn template_tree() -> TemplateNode {
    TemplateNode::Dir {
        name: "abserde_project",
        children: &[
            TemplateNode::Dir {
                name: "Schemas",
                children: &[
                    TemplateNode::Dir {
                        name: "Snapshots",
                        children: &[],
                    },
                    // Add an example schema file here
                ],
            },
            TemplateNode::Dir {
                name: "Profiles",
                children: &(
                    [
                        // Add an example profile file here
                    ]
                ),
            },
            // Add a TransactionSchemas file for Atomic Adds
        ],
    }
}

fn create_dir(path: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(path)?;
    Ok(())
}

fn write_file(path: &Path, content: &str) -> anyhow::Result<()> {
    let mut file = fs::OpenOptions::new().write(true).create(false).create_new(true).open(path)?;

    file.write_all(content.as_bytes())?;
    Ok(())
}

fn write_node(base: &Path, node: &TemplateNode) -> anyhow::Result<()> {
    match node {
        TemplateNode::File { name, content } => {
            let file_path = base.join(name);
            write_file(&file_path, content)?;
        }
        TemplateNode::Dir { name, children } => {
            let dir_path = base.join(name);
            create_dir(&dir_path)?;
            for child in *children {
                write_node(&dir_path, child)?;
            }
        }
    }
    Ok(())
}

pub fn run() -> anyhow::Result<()> {
    let cwd = std::env::current_dir()?;
    write_node(&cwd, &template_tree())?;
    Ok(())
}
